---
tags:
  - cours
  - parallelisme
  - openmp
  - hpc
up: "[[APP — MOC]]"
date: 2026-09-11
updated: 2026-10-16
status: à-réviser
source: "CM2 — cours2-slides.pdf (N. Maillard)"
---

# OpenMP

Se situe au-dessus des threads bruts : voir [[Parallélisme C++]] et le contexte matériel dans [[APP — MOC]].
Les tâches ont leurs propres notes : [[Tâches OpenMP — exemple Fibonacci]] et [[Tâches OpenMP — dépendances et taskloop]]. Le placement des threads est dans [[Affinité et placement des threads]].

> [!abstract] Le fil du CM2
> On part d'un séquentiel **correct** (règle d'or) → on parallélise → résultat **faux** (modèle mémoire) → on corrige avec la **mauvaise granularité** (`atomic`) → on corrige avec la **bonne** (`reduction`) → on **mesure** et on diagnostique ([[Lois d'Amdahl et de Gustafson|Amdahl, Karp-Flatt]]). L'étude de cas π en fin de note résume tout.

---

## D'où vient OpenMP

- **Parallélisme de données** : on décide comment répartir les données, des threads distincts travaillent sur des parties séparées. Simple à concevoir : il suffit de repérer où est le parallélisme dans les structures de données.
- Années 1990, **High-Performance Fortran** : l'idée qu'une simple recompilation d'un code existant suffirait. Échec dès que les dépendances cessent d'être simples.
- Le compromis retenu : un **petit ensemble d'annotations** que le programmeur ajoute pour aider le compilateur.

Ce que ça apporte :

- la compilation reste simple, avec quelques annotations (*pragmas*) ;
- on étend un compilateur traditionnel → **portabilité** indépendante du système ;
- intervention minime → réutilisation du code existant, moins d'erreurs.

> [!tip] Le compilateur peut ignorer les annotations
> Sans `-fopenmp`, les `#pragma omp` sont ignorés et on retrouve un programme **séquentiel** exécutable : c'est le code de référence pour vérifier la version parallèle.

Norme née en 1997–1998 (consortium constructeurs / programmeurs / utilisateurs), version **6.0** en novembre 2024. C, C++, Fortran. Dans gcc depuis la 4.2.

## Le modèle d'exécution : fork/join

```text
             thread primaire
  ───────────────●──────────────────────────●──────────────▶ temps
                 │ fork                join │
                 ├──── thread 1 ───────────┤
                 ├──── thread 2 ───────────┤   barrière implicite
                 └──── thread 3 ───────────┘
                 └──────── région parallèle ┘
```

Le programme démarre séquentiel. À une région parallèle, le thread engendre une **équipe** ; à la fin du bloc, tous se synchronisent et **un seul** continue. Cela peut se répéter et s'imbriquer.

| Terme | Sens |
| --- | --- |
| **Directive** | l'annotation (`#pragma omp parallel`) |
| **Construction** | directive + code qu'elle gouverne — **statique**, syntaxique |
| **Région** | ce qui est effectivement exécuté, y compris le code des fonctions appelées — **dynamique** |
| **Équipe** | l'ensemble des threads qui exécutent une région parallèle |
| **Thread primaire** | celui qui a rencontré la construction ; parent des autres ; le seul qui continue après |
| **Barrière implicite** | à la fin de toute région parallèle et de toute construction de partage du travail. Gratuite à écrire, coûteuse à exécuter |

> [!note] Construction ≠ région
> Cette distinction explique le [[#Piège nº 3 : les globales vues d'une fonction|piège des variables globales]] : les clauses ne s'appliquent qu'au texte de la construction, pas aux fonctions appelées dans la région.

La norme ne dit pas comment les threads OpenMP sont associés aux threads du système (gcc et clang font des choix différents) : on programme avec un modèle abstrait de threads.

## Deux notations

#### Notation historique avec `#pragma`

```c
#pragma omp parallel
hello();
```

#### Notation par attributs (C23, C++11) — celle du TP

```c
[[omp::directive(parallel)]]
hello();
```

> [!warning] Une différence de comportement
> Deux `#pragma` sur la même zone sont traités dans l'ordre écrit. Avec les attributs, le compilateur **pourrait les réordonner** : utiliser `omp::sequence(...)` pour imposer l'ordre. Les deux syntaxes peuvent coexister dans un fichier, mais pas sur la même instruction.

## Compilation et macro `_OPENMP`

```bash
gcc -std=gnu23 -fopenmp -O2 -Wall -Wextra -g hello.c -o hello
OMP_NUM_THREADS=5 ./hello
```

Sans `-fopenmp`, les pragmas sont ignorés **silencieusement**, mais pas `#include <omp.h>` ni les appels `omp_*` : erreur de compilation. La norme définit donc la macro `_OPENMP` :

```c
#ifdef _OPENMP
#include <omp.h>
#endif

int nb_threads = 1;
#ifdef _OPENMP
nb_threads = omp_get_max_threads();
#endif
```

### Un premier programme

```c
#include <stdio.h>
#include <omp.h>

int main(void) {
    #pragma omp parallel
    {
        int t_id = omp_get_thread_num();          // déclaré DANS le bloc → privé
        printf("Bonjour du thread %d sur %d\n", t_id, omp_get_num_threads());
    }                                             // barrière implicite
    printf("Ceci n'est affiché que par un seul thread.\n");
}
```

```text
Bonjour du thread 0 sur 3
Bonjour du thread 2 sur 3
Bonjour du thread 1 sur 3
Ceci n'est affiché que par un seul thread.
```

- L'ordre **change d'une exécution à l'autre** : rien ne le contraint.
- `omp_get_num_threads()` = combien de threads ; `omp_get_thread_num()` = mon identifiant. Ne pas confondre.
- Approche **SPMD** : un seul programme, exécuté par tous les threads, qui se distinguent par leur identifiant (même idée qu'en [[Mémoire partagée vs mémoire distribuée#Le modèle SPMD|MPI]]).

## Catégories de directives

| # | Catégorie | Question | Directives |
| --- | --- | --- | --- |
| 1 | Régions parallèles | créer les threads | `omp parallel` |
| 2 | Partage des données | qui voit quoi | `shared`, `private`, `firstprivate`, `lastprivate`, `threadprivate`, `default` |
| 3 | Distribution du travail | qui fait quoi | `omp for`, `omp sections`, `omp single` |
| 4 | Synchronisation | qui attend qui | `barrier`, `critical`, `atomic`, `master`/`masked` |
| 5 | Bibliothèque et environnement | régler l'exécution | `omp_set_num_threads()`, `omp_get_thread_num()`, `OMP_NUM_THREADS`, `OMP_SCHEDULE` |

---

## Le partage des données

### Le modèle mémoire

OpenMP = mémoire partagée à **consistance relâchée** : chaque thread peut avoir temporairement sa propre vue (registres, caches), réconciliée par un *flush* — que les synchronisations font implicitement. Trois conséquences :

- un accès à une variable peut être un *load* puis un *store* : il n'est **pas atomique** ;
- deux accès non ordonnés à la même adresse, dont au moins une écriture ⇒ **data race**, comportement indéterminé (voir [[Parallélisme C++#Data race]]) ;
- OpenMP ne protège **rien** implicitement. `private` n'est pas une protection, c'est une **duplication**.

### Shared et private

Chaque variable d'un bloc a une **variable d'origine** : celle du même nom, immédiatement à l'extérieur.

| Clause | Effet |
| --- | --- |
| `shared(x)` | toute référence désigne l'originale : un seul emplacement, accédé en concurrence |
| `private(x)` | une nouvelle copie par thread, **non initialisée** ; l'original n'est pas modifié |
| `firstprivate(x)` | copie privée **initialisée** avec la valeur d'entrée |
| `lastprivate(x)` | la valeur de la **dernière itération** (ordre séquentiel) ressort du bloc |
| `default(none)` | oblige à déclarer le statut de **chaque** variable |

Les clauses s'appliquent à une variable entière : pas de champ de `struct` partagé seul. Une variable peut être à la fois `firstprivate` et `lastprivate`.

**Règles par défaut :**

- variable déclarée **dans** le bloc → dans la pile du thread → **privée** d'office ;
- variable globale ou d'une portée englobante (celles du `main`) → **partagée** ;
- variable de contrôle de la boucle **immédiatement** sous un `omp for` → privée.

> [!tip] Déclarer au plus près de l'utilisation
> Déclarer les variables dans le bloc élimine la plupart des `private`. Règle générale : **devoir écrire dans une variable** est un indice sérieux qu'elle doit être privée.

### Piège nº 1 : `private` n'initialise pas

```c
double facteur = 0.5;
#pragma omp parallel for private(facteur)       // copie NON initialisée
for (int i = 0; i < N; i++)
    c[i] = facteur * a[i];                      // c[0] = 0, attendu 0.5
```

Correction : `firstprivate(facteur)` (ou rien du tout : partagée en lecture seule, c'est sûr). gcc prévient avec `-Wall -Wextra` : `'facteur' may be used uninitialized`.

### Piège nº 2 : la boucle imbriquée

```c
int i, j;
#pragma omp parallel for            // i privée... mais j PARTAGÉE
for (i = 0; i < N; i++)
    for (j = 0; j < N; j++)         // tous les threads écrivent j++ → data race
        c[i] += a[i] + b[j];
```

La règle « variable de boucle privée » ne vaut que pour la boucle **immédiatement** sous la directive. Correction : `private(j)`, ou mieux `for (int j = 0; ...)`.

### `default(none)`, la discipline qui sauve

```c
#pragma omp parallel for default(none) shared(a, b, c)
```

Le défaut « partagé » est le défaut **dangereux**. Avec `default(none)`, le compilateur refuse de compiler tant qu'on n'a pas statué sur chaque variable : fastidieux, et c'est exactement pour ça que c'est utile.

### Piège nº 3 : les globales vues d'une fonction

```c
int n = 10;
void imprime(void) { printf("imprime() voit n = %d\n", n); }

#pragma omp parallel private(n)
{
    printf("dans le bloc, n = %d\n", n);   // copie privée, non initialisée : 0
    imprime();                             // ... mais ici, c'est le n GLOBAL : 10
}
```

Les clauses ne gouvernent que les accès **écrits textuellement** dans la construction ; une fonction appelée voit toujours la variable partagée. Une même variable, deux valeurs, à deux lignes d'intervalle.

**Correctif : `threadprivate`** — chaque thread a sa propre copie de la globale, y compris à travers les appels de fonction ; `copyin` y recopie la valeur du thread primaire.

```c
int n = 10;
#pragma omp threadprivate(n)
...
#pragma omp parallel copyin(n)      // dans le bloc ET dans imprime() : n = 10
```

> [!note] Correction ≠ performance
> Deux threads qui écrivent `x` et `y` n'ont aucun conflit logique… mais peuvent subir du [[Localité et caches#Le faux partage|faux partage]] si `x` et `y` sont dans la même ligne de cache.

---

## La distribution du travail

### `sections`

```c
#pragma omp parallel
#pragma omp sections
{
    #pragma omp section
    f1();
    #pragma omp section
    f2();
    #pragma omp section
    f3();
}
```

Moins de threads que de sections → un thread en exécute plusieurs (et même avec assez de threads, un seul peut tout faire). **Intérêt limité** : le parallélisme est codé en dur — avec 4 threads, il n'y a pas de `f4` à donner au quatrième. Ça ne passe pas à l'échelle, d'où le parallélisme de boucles.

### `omp for`

```c
// À la main, en SPMD                       // Confié au runtime
#pragma omp parallel                         #pragma omp parallel for
{                                            for (int i = 0; i < N; i++)
    int id = omp_get_thread_num();               a[i] = a[i] + b[i];
    int nb = omp_get_num_threads();
    int debut = id * N / nb;
    int fin   = (id + 1) * N / nb;
    for (int i = debut; i < fin; i++)
        a[i] = a[i] + b[i];
}
```

La version `omp for` est plus courte, plus sûre (pas d'erreur de bornes), et laisse au runtime le choix de l'ordonnancement (`schedule`). La version SPMD reste utile quand la répartition suit une logique que `omp for` ne sait pas exprimer.

> [!example] Défaut délibéré du cours
> ```c
> int tid;                                   // déclarée hors du bloc → partagée
> #pragma omp parallel for
> for (i = 0; i < N; i++) {
>     tid = omp_get_thread_num();            // tous écrivent tid : data race
>     if (tid == 0) printf("thread 0 calcule i = %d\n", i);   // vrai pour n'importe qui
> }
> ```
> À passer à ThreadSanitizer (voir [[Compiler, déboguer, mesurer#La boîte à outils]]). Correction : déclarer `tid` dans la boucle.

**Forme canonique** : OpenMP doit connaître le nombre d'itérations **avant** d'entrer dans la boucle.

```c
for (i = début; i op_rel fin; op(i))
```

- `i`, `début`, `fin` entiers, connus à l'entrée ; `op_rel ∈ {<, >, <=, >=}` ;
- `op(i)` : incrément constant (`i++`, `i += K`…) ;
- ni `break`, ni `goto`. Donc **pas de `while`** : il faut repasser en SPMD (voir [[#Le cas qui la rend nécessaire : le task-farm|task-farm]]) ou utiliser des tâches.

### `nowait` et `collapse`

```c
#pragma omp parallel
{
    #pragma omp for nowait            // pas de barrière en sortie
    for (int i = 0; i < N; i++) a[i] = f(i);
    #pragma omp for
    for (int i = 0; i < N; i++) b[i] = g(i);
}
```

> [!warning] `nowait` à manier avec précaution
> Si la seconde boucle **lit** `a`, retirer la barrière introduit une data race.

`collapse(n)` fusionne $n$ boucles imbriquées en un seul espace d'itérations : utile quand la boucle externe est trop courte pour occuper tous les threads.

### La clause `schedule`

`schedule` dit quel thread traite quelle itération (CM3–CM4) :

| `schedule(...)` | Répartition |
| --- | --- |
| `static` | un bloc contigu par thread, fixé d'avance (**défaut**) |
| `static, c` | paquets de `c` itérations distribués à tour de rôle |
| `dynamic, c` | paquets de `c` (défaut 1), pris par les threads libres |
| `guided, c` | paquets de taille décroissante (au moins `c`) |
| `runtime` | lu dans la variable `OMP_SCHEDULE` — change sans recompiler |

- `dynamic` et `guided` **équilibrent la charge** quand les itérations ont des durées inégales, au prix d'un surcoût.
- `static` est **déterministe** : deux boucles de même nombre d'itérations sous `schedule(static)` donnent les mêmes itérations aux mêmes threads. C'est la base du *first touch* — voir [[NUMA et mémoire virtuelle#La politique first touch]] et [[Affinité et placement des threads]].

---

## La réduction

Un schéma très fréquent : `res += f(...)` dans une boucle. Somme de 10 000 « uns » avec 4 threads, réponse attendue 10 000 :

| Tentative | Code | Résultat | Pourquoi |
| --- | --- | --- | --- |
| 1 | `private(somme)` | **0** | copies non initialisées, et perdues à la sortie |
| 2 | `firstprivate(somme) lastprivate(somme)` | **2500** | seule la copie du thread qui a fait l'itération $N-1$ ressort : $10\,000/4$ |
| 3 | `reduction(+ : somme)` | **10000** | ✅ |

```c
int somme = 0;
#pragma omp parallel for reduction(+ : somme)
for (int i = 0; i < N; i++) somme += a[i];
```

Ce que le compilateur engendre :

1. une copie privée par thread, initialisée à l'**élément neutre** (0 pour `+`, 1 pour `*`) ;
2. l'accumulation locale dans cette copie ;
3. à la sortie, la **combinaison** de toutes les copies dans la variable d'origine.

Opérateurs : `+ * - & | ^ && ||`, `min`, `max`. `declare reduction` pour définir les siens.

> [!warning] Associativité et flottants
> L'ordre de combinaison n'est **pas spécifié** : l'opération doit être associative. Or l'addition flottante ne l'est pas : une réduction peut donner un résultat différent du séquentiel, et différent d'une exécution à l'autre si le nombre de threads change.
> ```text
> séquentiel : 3.141592653590426
> réduction  : 3.141592653589816
> ```
> Les deux sont « justes ». On ne valide **pas** une parallélisation avec `diff` sur des flottants : on compare à une tolérance près. (Même problème avec `-ffast-math`, voir [[Compiler, déboguer, mesurer]].)

---

## La synchronisation

### Le cas qui la rend nécessaire : le task-farm

Boucle dont on ne connaît pas le nombre d'itérations → pas de `omp for` → retour au SPMD, avec un indice partagé :

```c
static int indice = 0;
int indice_suivant(void) {          // ❌ FAUX : data race sur indice
    int res;
    if (indice >= N) res = -1;
    else             res = indice++;
    return res;
}

#pragma omp parallel
{
    int i = indice_suivant();
    while (i != -1) { calcul(i); i = indice_suivant(); }
}
```

```text
taches executees = 7999972 (attendu : 1000000)
taches executees = 6999979 (attendu : 1000000)
```

Faux, et faux différemment à chaque fois : jusqu'à 8 fois trop de tâches, car les threads lisent le même indice et refont le même travail. C'est le schéma **maître/travailleurs** : très général, c'est la solution de base à l'équilibrage de charge… mais la centralisation devient un goulot (→ vol de travail, CM10).

### `critical`

```c
int indice_suivant(void) {
    int res;
    #pragma omp critical(indice_partage)     // ✅ section critique NOMMÉE
    {
        if (indice >= N) res = -1;
        else             res = indice++;
    }
    return res;
}
```

> [!tip] Nommer ses sections critiques
> Une section critique **anonyme** est en exclusion mutuelle avec **toutes** les autres sections anonymes du programme, même sans rapport. Deux sections de noms différents s'exécutent en même temps. Sur un gros programme, c'est la différence entre un code parallèle et un code qui en a l'air.

### `atomic`, `barrier`, `single`, `master`

| Directive | Effet |
| --- | --- |
| `atomic` | `critical` léger, limité à l'instruction suivante si elle fait un unique accès mémoire (`compteur++`). Traduit en **instruction matérielle**, pas en verrou |
| `barrier` | barrière explicite (il y en a déjà une implicite en fin de région et de partage du travail) |
| `single` | un thread et un seul, peu importe lequel (typiquement des E/S). **Barrière implicite** en sortie |
| `master` / `masked` (5.1) | le thread primaire. **Pas** de barrière |

`single` et `master` remplacent avantageusement les `if (t_id == 0) ...`.

### Verrous, bibliothèque, environnement

- **Verrous** : `omp_lock_t`, `omp_init_lock`, `omp_set_lock`, `omp_unset_lock`, `omp_destroy_lock`. Le plus général et le plus dangereux : vous devenez responsable des interblocages. Préférer les directives quand elles suffisent.
- Les **fonctions** `omp_*` ne disparaissent pas sans `-fopenmp` (contrairement aux directives).
- Les **variables d'environnement** donnent les mêmes réglages sans toucher au code : `OMP_NUM_THREADS`, `OMP_SCHEDULE`, `OMP_PROC_BIND`, `OMP_PLACES`. Très supérieur pour mesurer : le tableau de Karp-Flatt du cours a été produit sans recompiler.
- Le nombre de threads demandé est **indicatif** : l'implémentation peut en utiliser moins.

---

## Étude de cas : π en quatre versions

$\pi = \int_0^1 \frac{4}{1+x^2}\,dx$, méthode du point milieu, $10^8$ pas — c'est le `pi.c` du TP 1 (`TP/srcTP1/pi.c`).

```c
// v1 — séquentielle
for (uint64_t i = 0; i < NB_STEPS; i++) {
    double const x = (i + 0.5) * step;
    sum += 4. / (1. + x * x);
}

// v2 — naïve : sum est PARTAGÉE → data race
#pragma omp parallel for

// v3 — atomic sur chaque addition
#pragma omp parallel for
    ...
    #pragma omp atomic
    sum += 4. / (1. + x * x);

// v4 — réduction
#pragma omp parallel for reduction(+ : sum)
```

| Version | Résultat | Temps (s) | Verdict |
| --- | --- | --- | --- |
| séquentielle | 3,141592653590426 | 0,101 | référence |
| `parallel for` | 0,3396… (varie) | 0,025 | **faux** — et 4× plus rapide |
| `+ atomic` | 3,141592653589766 | **13,300** | juste, **132× plus lent** |
| `reduction` | 3,141592653589815 | 0,019 | juste, $S_8 = 5{,}3$ |

> [!danger] La v2 est la situation la plus dangereuse
> Une accélération flatteuse est très convaincante. Si elle avait affiché 3,09 au lieu de 0,339, l'auriez-vous remarqué ? Et la valeur change à chaque exécution.

> [!note] Pourquoi `atomic` est si lent
> Chaque itération sérialise l'accès à `sum` : les 8 cœurs se disputent **une seule ligne de cache**, qui fait la navette — on a reconstruit, en pire, le [[Localité et caches#Le faux partage|faux partage]]. Le problème n'était pas la correction, mais la **granularité de la synchronisation** : la réduction fait une synchronisation **par thread** au lieu d'une **par itération**.

## Check-list

1. Le code séquentiel est-il correct et optimisé ? Sinon, s'arrêter là.
2. Compilé en `-O2` au moins ?
3. Avertissements lus ? (`-Wall -Wextra`)
4. Chaque variable correctement partagée ? (`default(none)`)
5. Les boucles internes ont-elles leurs variables privées ?
6. Une variable écrite par tous est-elle protégée — ou mieux, **réduite** ?
7. Les sections critiques sont-elles nommées ?
8. Vérifié avec ThreadSanitizer ?
9. Résultat comparable au séquentiel, à une tolérance près ?
10. Mesuré plusieurs fois, médiane donnée ?
11. Speedup **absolu** ou **relatif** ? Le dire.
12. Si ça plafonne : Amdahl, ou surcoût ? → [[Lois d'Amdahl et de Gustafson#Mesurer α : la métrique de Karp-Flatt|Karp-Flatt]].

## Voir aussi

- [[Tâches OpenMP — exemple Fibonacci]] · [[Tâches OpenMP — dépendances et taskloop]] — le parallélisme irrégulier
- [[Affinité et placement des threads]] — `OMP_PLACES`, `OMP_PROC_BIND`, first touch
- [[Compiler, déboguer, mesurer]] — `-O2`, ThreadSanitizer, `perf`, mesurer sans se mentir
- [[Lois d'Amdahl et de Gustafson]] — ce qu'on peut espérer
- [[MPI]] — la mémoire distribuée, souvent combinée à OpenMP : voir [[MPI — programmation hybride avec OpenMP]]

## Sources

- CM2, *Les concepts du parallélisme — OpenMP* (`CM/cours2-slides.pdf`)
- TP1 OpenMP : `TP/tp1-OMP.pdf`, sources `TP/srcTP1/`
- OpenMP Application Programming Interface 6.0, nov. 2024 — <https://www.openmp.org/specifications/>
