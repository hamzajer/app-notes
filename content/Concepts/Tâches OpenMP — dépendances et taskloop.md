---
tags:
  - cours
  - parallelisme
  - openmp
  - ordonnancement
up: "[[APP — MOC]]"
date: 2026-10-16
status: à-réviser
source: "CM4 — openmp-numa-affinity-memoirevirtuelle.pdf ; TP2/TP3 OpenMP"
---

# Tâches OpenMP — dépendances et taskloop

> [!abstract] En une phrase
> `depend` dit **quand** une tâche peut s'exécuter (l'ordre entre sœurs), `taskwait`/`taskgroup` disent **qui attend quoi**, et `taskloop` découpe une boucle en tâches qui s'équilibrent toutes seules.

Les bases (`task`, `taskwait`, granularité, `if`/`final`) sont dans [[Tâches OpenMP — exemple Fibonacci]] ; le modèle ($W$, $CP$, Graham) dans [[Ordonnancement et théorème de Graham]].

## Rappels

```c
long fibo(int n) {
    if (n < 30) return fibo_seq(n);     // seuil : assez de travail par tâche
    long n1, n2;
    #pragma omp task shared(n2)
    n2 = fibo(n - 2);
    n1 = fibo(n - 1);                   // le thread courant fait l'autre appel
    #pragma omp taskwait                // attend les tâches filles
    return n1 + n2;
}
```

- Une tâche = un bloc de code **et ses données**, exécuté plus tard par un thread quelconque de l'équipe.
- On crée les tâches depuis **un seul** thread : `parallel` puis `single` (ou `masked`).
- Le grain : un seuil séquentiel, ou `final(...)` et `mergeable`.

> [!important] Attributs de partage par défaut dans une tâche
> Une variable `shared` dans le contexte englobant reste `shared` ; **toute autre** variable — en particulier les **variables locales et les paramètres** d'une fonction — devient **`firstprivate`** : la tâche en reçoit une copie, faite **à sa création**. Pour récupérer un résultat, il faut donc `shared(...)`.

Le graphe de tâches a une version **dataflow** : les données sont aussi des nœuds, et les arcs disent qui les produit et qui les consomme. Ordonnancement de liste : $T \le W/m + CP$.

## `depend` : l'ordre entre tâches sœurs

| 1ʳᵉ tâche | 2ᵉ tâche | Il faut… | Dépendance |
| --- | --- | --- | --- |
| `out: x` | `in: x` | écrire avant de lire | **vraie** (*flow*) |
| `in: x` | `out: x` | lire avant d'écraser | **anti** |
| `out: x` | `out: x` | garder la dernière écriture | **de sortie** |
| `in: x` | `in: x` | rien : lectures concurrentes | aucune |

- Le sens des arcs vient de **l'ordre de création** des tâches : c'est le programme séquentiel qui fait foi.
- Sans `depend`, deux tâches sœurs ne sont ordonnées **d'aucune façon**.
- Les dépendances ne relient que des **tâches sœurs** (même tâche mère).

### Une chaîne : `depend(inout: ...)`

```c
for (int i = 0; i < N; i++)
    #pragma omp task shared(R) firstprivate(i) depend(inout: R)
    { travail(i); R += i; printf("%d ", i); }

#pragma omp task shared(R) depend(in: R)
printf("\nR = %d\n", R);
```

```text
0 1 2 3 4 5 6 7
R = 28                 inout : 0.39 s   (la tâche i dure (8 - i) centièmes → 0,36 s de travail)
```

`inout` : chaque tâche lit et écrit `R`, donc dépend de la précédente → **une chaîne**, exécution séquentielle dans l'ordre de création. Aucun parallélisme.

### Accumuler sans ordre : `mutexinoutset` et `inoutset`

```c
#pragma omp task shared(R) firstprivate(i) depend(mutexinoutset: R)   // 5.0
#pragma omp task shared(R) firstprivate(i) depend(inoutset: R)        // 5.1
{
    travail(i);
    #pragma omp atomic          // requis avec inoutset
    R += i;
}
```

| Clause | Ordre | Exclusion mutuelle | `atomic` | Temps (s) |
| --- | --- | --- | --- | --- |
| `inout` | de création | oui (chaîne) | inutile | 0,39 |
| `mutexinoutset` (5.0) | quelconque | **oui** | inutile | 0,39 |
| `inoutset` (5.1) | quelconque | **non** | **requis** | **0,09** |

Dans les trois cas, la tâche `depend(in: R)` attend toutes les autres. Avec `mutexinoutset`, l'ordre observé peut ressembler à celui de création, mais rien ne le garantit — et comme `travail(i)` est dans la section exclusive, on ne gagne rien ici.

### Dépendre de tout un tableau : `iterator`

```c
for (int i = 0; i < N; i++)
    #pragma omp task shared(v) firstprivate(i) depend(out: v[i])
    { usleep(10000 * (i + 1)); v[i] = i * i; }

#pragma omp task shared(v) depend(iterator(it = 0:N), in: v[it])    // 5.0
{ int somme = 0; for (int i = 0; i < N; i++) somme += v[i]; }
```

`iterator(it = 0:N)` : **une** clause, $N$ dépendances `in: v[0]`, …, `in: v[N-1]`.

> [!warning] Pourquoi pas `depend(in: v[0:N])` ?
> Les zones nommées dans les `depend` de tâches sœurs doivent être **identiques ou disjointes** : le recouvrement partiel de `v[0:N]` et `v[i]` n'est pas défini par la norme. (C'est aussi la réponse à la question 3.18 du TP2.)
> Rappel de syntaxe : `t[i:n]` = section qui **commence** à `i` et a pour **longueur** `n` (pas l'indice de fin).

## Qui attend quoi ?

### `taskwait depend` : n'attendre qu'une tâche

```c
#pragma omp taskwait depend(in: v[0])        // 5.0 : seulement les tâches dont dépend v[0]
printf("%.2f s : v[0] = %d\n", omp_get_wtime() - t0, v[0]);
```

```text
0.01 s : v[0] = 0          ← le plus souvent
0.09 s : v[0] = 0          ← parfois !
```

> [!note] Une attente garantit un minimum, jamais un maximum
> `taskwait` est un **point d'ordonnancement** : en attendant, le thread peut exécuter lui-même une autre tâche prête, éventuellement plus longue.

### `taskwait` vs `taskgroup`

```c
#pragma omp task                          #pragma omp taskgroup
{                                         {
    #pragma omp task                          #pragma omp task
    petite_fille();                           {
    printf("fille terminée\n");                   #pragma omp task
}                                                 petite_fille();
#pragma omp taskwait                              printf("fille terminée\n");
printf("après taskwait\n");                   }
                                          }
                                          printf("après taskgroup\n");
```

```text
fille terminée                            fille terminée
après taskwait                            petite-fille terminée
petite-fille terminée   ← pas attendue    après taskgroup
```

| Construction | Attend la fin de… |
| --- | --- |
| `taskwait` | les tâches **filles** de la tâche courante (pas les petites-filles) |
| `taskgroup` | les tâches créées dans le bloc **et toutes leurs descendantes** |
| `taskwait depend(...)` | les seules tâches dont on dépend |
| barrière (explicite, ou implicite en fin de `single` / `parallel`) | **toutes** les tâches de l'équipe |

La fin de `single` et la fin de `parallel` sont des barrières implicites : aucune tâche ne leur survit. `taskgroup` permet d'attendre un travail **récursif** (un parcours d'arbre) sans bloquer les autres tâches en cours — c'est la réponse à la V2 du tri fusion (TP2, Q3.13) : après `fusion_dicho`, un `taskwait` n'attend pas les sous-tâches récursives.

## `taskloop` : une boucle découpée en tâches

```c
#pragma omp parallel
#pragma omp single
#pragma omp taskloop grainsize(1000)          // ou num_tasks(64)
for (int i = 0; i < n; i++)
    calcul(i);
```

- `grainsize(g)` : entre $g$ et $2g$ itérations par tâche ;
- `num_tasks(t)` : $t$ tâches ;
- un **`taskgroup` implicite** entoure la boucle ; `nogroup` le supprime.

Différence avec `omp for` : **aucune répartition fixée d'avance**. Les tâches sont prises par les threads libres et se mêlent aux autres tâches en cours : l'équilibrage de charge est automatique.

### Le piège : `taskloop` ne partage pas le travail

```c
#pragma omp parallel num_threads(4) shared(x)
#pragma omp taskloop                    // chaque thread de l'équipe crée TOUTES les tâches
for (int i = 0; i < N; i++)
    #pragma omp atomic
    x++;

#pragma omp parallel masked taskloop num_threads(4) shared(x)    // forme combinée
for (int i = 0; i < N; i++)
    #pragma omp atomic
    x++;
```

```text
piege  : x = 80        (N = 20, 4 threads : 4 × 20 itérations)
masked : x = 20
```

*Vérifié avec gcc 13.3 (`-fopenmp`).* Il faut **un seul créateur** : `single`, ou `masked` (5.1, remplace `master`). C'est la question 2.1 du TP2 (`pi_piege`).

### Réduction sur `taskloop`

```c
double h = 1.0 / PAS, somme = 0.0;
#pragma omp parallel masked taskloop grainsize(1000000) reduction(+: somme)
for (long i = 0; i < PAS; i++) {
    double x = (i + 0.5) * h;
    somme += 4.0 / (1.0 + x * x);
}
```

`reduction` sur `taskloop` (5.0) : une copie privée **par tâche**, combinées à la fin du `taskgroup` implicite. Pour des tâches créées une à une : `task_reduction(+: s)` sur le `taskgroup`, et `in_reduction(+: s)` sur chaque `task` qui y participe.

## En TP

### TP2 — tri par fusion

Sources : `TP/srcTP2/tri_fusion.c`.

| Version | Idée | Chemin critique |
| --- | --- | --- |
| **V1** | les 2 appels récursifs = 2 tâches, `taskwait` avant la fusion séquentielle | $T_\infty = \Theta(n)$ : les fusions d'une branche ($n + n/2 + n/4 + \dots \le 2n$), d'où $S \le T_1/T_\infty = \Theta(\log n)$ |
| **V2** | fusion **par dichotomie** (`fusion_dicho`) : le médian $x$ de la plus longue suite a pour place $m_a + m_b$, puis deux fusions indépendantes ; `taskgroup` pour attendre ; recopie en `taskloop` | $\Theta(\log^3 n)$ si la recopie est aussi parallèle (CLRS 3ᵉ éd., §27.3) ; $\Theta(n)$ si la recopie reste un `memcpy` séquentiel |
| **V3** | tri **ascendant** : blocs de `seuil` triés, puis fusions 2 à 2 niveau par niveau ; un seul thread crée tout, `depend` sur le **premier élément** de chaque bloc | la fusion des blocs 0-1 peut commencer avant la fin du tri du bloc 7 |

Trois façons de couper la récursion (Q3.6–3.9) : clause `if(hi - lo > seuil)`, clause `final(...)` + `omp_in_final()`, ou **bascule explicite** `if (hi - lo <= seuil) return tri_seq(...)`. La clause `if` est la moins efficace : avec une condition fausse, une tâche est **quand même créée** (tâche *non différée*, exécutée tout de suite par le thread courant) avec son environnement de données — on paie encore une partie du surcoût à chaque appel, jusqu'aux feuilles. La bascule explicite, elle, ne crée plus rien sous le seuil.

> [!question] Pourquoi pas `depend` dans la V1 récursive ? (Q3.19)
> `depend` ne relie que des **sœurs**, et une tâche est terminée quand **son bloc** est fini — pas ses descendantes. La tâche de fusion pourrait donc démarrer alors que les sous-tâches des deux tris tournent encore.

### TP3 — Cholesky par blocs

Sources : `TP/srcTP3/cholesky.c`.

$A = LL^T$, matrice découpée en $nt \times nt$ blocs $b \times b$ contigus, quatre noyaux :

```text
pour k = 0 .. nt-1
    POTRF(Akk)                 Akk = Lkk Lkk^T
    pour i > k : TRSM(Akk, Aik)         Aik = Aik Lkk^-T
    pour i > k : SYRK(Aik, Aii)         Aii -= Aik Aik^T
        pour k < j < i : GEMM(Aik, Ajk, Aij)   Aij -= Aik Ajk^T
```

La version `fj` (*fork-join*, un `omp for` par étape) met une barrière entre chaque étape alors que le graphe de tâches ne l'exige pas : le `POTRF` de l'étape $k+1$ n'attend que les mises à jour (`SYRK`) de **son** bloc, pas tous les `GEMM` de l'étape $k$ — ceux-ci peuvent se recouvrir avec l'étape suivante. Version tâches : `depend(in: Akk[0:b*b])`, `depend(inout: Aij[0:b*b])`… — chaque bloc désigné par la section qui le contient en entier. Performance affichée en Gflop/s : $n^3/3$ opérations divisées par le temps.

## Voir aussi

- [[Tâches OpenMP — exemple Fibonacci]] — `task`, `taskwait`, granularité, `if` vs `final`
- [[Ordonnancement et théorème de Graham]] — $W$, $CP$, borne de Graham
- [[Affinité et placement des threads#Tâches et NUMA]] — les tâches perdent le first touch
- [[OPENMP]] — directives de base

## Sources

- CM4, *Tâches (suite), NUMA et affinité mémoire* (`CM/openmp-numa-affinity-memoirevirtuelle.pdf`), partie « Les opérateurs sur les tâches »
- TP2 OpenMP, *La programmation par tâches* (`TP/tp2-OMP-taches.pdf`, `TP/srcTP2/`) — aide-mémoire en annexe A
- TP3 OpenMP, *Graphes de tâches et localité* (`TP/tp3-OMP-taches.pdf`, `TP/srcTP3/`)
