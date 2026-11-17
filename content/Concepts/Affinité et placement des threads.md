---
tags:
  - cours
  - parallelisme
  - openmp
  - numa
  - performance
up: "[[APP — MOC]]"
date: 2026-10-16
status: à-réviser
source: "CM4 — openmp-numa-affinity-memoirevirtuelle.pdf ; TP3 — tp3-OMP-taches.pdf"
---

# Affinité et placement des threads

> [!abstract] En une phrase
> Pour qu'un thread trouve ses données près de lui, il faut **trois ingrédients à la fois** : une initialisation parallèle (*first touch*), le **même découpage** des itérations à l'initialisation et au calcul, et des threads **attachés** qui ne quittent pas le nœud de leurs pages.

Le modèle matériel (nœuds, pages, first touch) est dans [[NUMA et mémoire virtuelle]].

## La question du cours

Même calcul, même nombre de threads, même binaire. Une seule différence : **qui écrit en premier** dans les tableaux.

```c
// Version A : init séquentielle                // Version B : init parallèle
for (size_t i = 0; i < n; i++) {                #pragma omp parallel for schedule(static)
    a[i] = 0.0; b[i] = 1.0; c[i] = 2.0;         for (size_t i = 0; i < n; i++) {
}                                                   a[i] = 0.0; b[i] = 1.0; c[i] = 2.0;
                                                 }
#pragma omp parallel for schedule(static)       #pragma omp parallel for schedule(static)
for (size_t i = 0; i < n; i++)                  for (size_t i = 0; i < n; i++)
    a[i] = b[i] + s * c[i];                         a[i] = b[i] + s * c[i];
```

Sur une machine NUMA, on attend **B ≫ A** : A met tout sur un seul nœud (accès distants, un seul contrôleur) ; B place chaque page près du thread qui la calculera.

## Les places : `OMP_PLACES`

Une **place** = un ensemble de processeurs (au sens du système) où un thread peut s'exécuter.

| `OMP_PLACES` | Une place = | Depuis |
| --- | --- | --- |
| `threads` | un processeur logique (hyper-thread) | 4.0 |
| `cores` | un cœur physique (et ses hyper-threads) | 4.0 |
| `sockets` | un socket | 4.0 |
| `ll_caches` | les cœurs qui partagent le dernier niveau de cache | 5.0 |
| `numa_domains` | un nœud NUMA | 5.0 |
| `"{0:4},{4:4}"` | liste explicite : `{0,1,2,3}`, `{4,5,6,7}` | 4.0 |

Syntaxe : `"{0},{2},{5}"` = trois places explicites ; `"{4}:4"` = les quatre places `{4}` … `{7}`.

> [!note] Seule, `OMP_PLACES` ne fait rien
> Elle définit **où l'on peut** placer. C'est `OMP_PROC_BIND` qui attache.

## L'attachement : `OMP_PROC_BIND`

| Valeur | Effet |
| --- | --- |
| `false` | pas d'attachement : l'OS déplace les threads à sa guise |
| `true` | attachés, placement laissé à l'implémentation |
| `primary` | tous sur la place du thread principal (`master` avant 5.1) |
| `close` | sur des places **consécutives**, à partir de celle du principal |
| `spread` | **étalés** régulièrement sur toutes les places |

En clause : `#pragma omp parallel proc_bind(close)`.

```text
4 threads, OMP_PLACES=cores, 2 nœuds de 4 cœurs
                 ┌──────── nœud 0 ────────┐┌──────── nœud 1 ────────┐
                   c0    c1    c2    c3      c4    c5    c6    c7
close              T0    T1    T2    T3      ·     ·     ·     ·
spread             T0    ·     T1    ·       T2    ·     T3    ·
```

### `close` ou `spread` ?

Aucun n'est meilleur dans l'absolu.

| | Pour | Contre |
| --- | --- | --- |
| **`close`** | les threads partagent les caches et le nœud : bon s'ils échangent beaucoup de données, ou si le problème tient dans le cache | code limité par le débit mémoire : **un seul contrôleur** travaille |
| **`spread`** | les threads couvrent tous les nœuds : **tous les contrôleurs** travaillent | à condition que chaque thread trouve ses données sur son nœud (*first touch* !) |

> [!tip] Règle de départ pour un code de calcul
> `OMP_PLACES=cores OMP_PROC_BIND=spread` (ou `close` quand tous les cœurs sont occupés : les deux coïncident alors). Puis **mesurer**.

## Vérifier le placement

```bash
OMP_DISPLAY_AFFINITY=true OMP_PROC_BIND=spread ./prog   # placement de chaque thread
OMP_DISPLAY_ENV=true ./prog                             # la configuration retenue
```

Depuis le code : `omp_get_num_places()`, `omp_get_place_num()` (4.5), `omp_get_place_num_procs(p)`, `omp_get_place_proc_ids(p, ids)`, `omp_display_affinity()` et `OMP_AFFINITY_FORMAT` (5.0). Côté Linux : `sched_getcpu()`, `getcpu(&coeur, &noeud)`.

> [!example] Exemple 2 du cours : qui tourne où ?
> Chaque thread relève son cœur, calcule ~1 s, puis relève à nouveau son cœur.
> ```text
> ===== OMP_PROC_BIND=false
> thread 1  place -1  coeur 4 -> 0  (a migré)
> thread 4  place -1  coeur 7 -> 1  (a migré)
> thread 0  place -1  coeur 2 -> 2
> ===== OMP_PROC_BIND=close
> thread 0  place 0   coeur 0 -> 0
> thread 1  place 1   coeur 1 -> 1
> ```
> Avec `false` : cœurs imprévisibles d'une exécution à l'autre, **migrations** possibles (place `-1` = pas de place). Avec `close`/`spread` : placement conforme au schéma, stable.

## La triade

```c
// Le premier accès décide du nœud de chaque page.
#pragma omp parallel for schedule(static) if (init_par)   // if faux → 1 seul thread
for (size_t i = 0; i < n; i++) { a[i] = 0.0; b[i] = 1.0; c[i] = 2.0; }

for (int r = 0; r < rep; r++) {
    double t0 = omp_get_wtime();
    #pragma omp parallel for schedule(static)              // MÊME schedule qu'à l'init
    for (size_t i = 0; i < n; i++)
        a[i] = b[i] + s * c[i];
    temps[r] = omp_get_wtime() - t0;
}
```

Débit compté comme STREAM : $3 \times 8 \times n$ octets par itération (le trafic réel est plus élevé : l'écriture de `a` commence par charger sa ligne).

Ce qu'on doit voir **sur une machine NUMA** :

- `seq` : le débit plafonne à celui d'**un** contrôleur, quel que soit le nombre de threads ;
- `par` + `spread` : le débit croît jusqu'à la **somme** des contrôleurs ;
- `par` + `close` avec peu de threads : tous sur le nœud 0, donc comme `seq` ; les deux se rejoignent quand tous les cœurs sont occupés ;
- `interleave` : entre les deux.

> [!example] Mesures du cours (1 seul nœud NUMA, débit en Go/s, médiane de 11)
> | threads | seq close | par close | seq spread | par spread | seq interleave |
> | --- | --- | --- | --- | --- | --- |
> | 1 | 4,82 | 5,40 | 4,84 | 5,88 | 16,54 |
> | 2 | 8,51 | 8,53 | 10,30 | 10,25 | 10,10 |
> | 4 | 16,86 | 14,46 | 17,35 | 20,61 | 19,22 |
> | 8 | 27,99 | 30,15 | 31,42 | 52,47 | 36,15 |
>
> Les quatre points ci-dessus **ne se vérifient pas** ici : un seul nœud = un seul contrôleur, rien à répartir. La croissance de 4,8 à 52 Go/s vient du parallélisme **intra-nœud** (cœurs, caches), et le 16,54 isolé est du bruit de mesure.

### Pourquoi le même `schedule(static)` ?

Pour que le thread qui calcule `a[i]` soit **celui qui l'a initialisé**.

- La norme **garantit** la même répartition entre deux boucles `schedule(static)` si elles ont le même nombre d'itérations, le même `chunk_size` (ou aucun) et se lient à la **même** région parallèle.
- Entre **deux régions** parallèles (comme ici) : pas garanti par la norme, mais les implémentations usuelles réutilisent les mêmes threads, attachés aux mêmes places. On le vérifie par la mesure.
- `schedule(dynamic)` : aucune garantie, les pages sont lues à distance au hasard.
- `schedule(static, 1)` : déterministe, mais **différent** du découpage par blocs de l'initialisation.

## Jacobi 2D : un calcul réaliste

Diffusion de la chaleur sur une plaque $n \times n$ : chaque point prend la moyenne de ses 4 voisins. Deux tableaux de 128 Mio ($n = 4096$), peu de calcul par octet : un code **limité par le débit mémoire** (voir [[Compiler, déboguer, mesurer#Limité par le calcul ou par la mémoire ?|intensité arithmétique]]).

```c
static void initialiser(double *u, size_t n, bool par) {
    #pragma omp parallel for schedule(static) if (par)
    for (size_t i = 0; i < n; i++)
        for (size_t j = 0; j < n; j++)
            U(i, j) = (i == 0) ? 100.0 : 0.0;
}

static void iterer(const double *restrict u, double *restrict v, size_t n) {
    #pragma omp parallel for schedule(runtime)     // lu dans OMP_SCHEDULE
    for (size_t i = 1; i < n - 1; i++)
        for (size_t j = 1; j < n - 1; j++)
            V(i, j) = 0.25 * (U(i-1, j) + U(i+1, j) + U(i, j-1) + U(i, j+1));
}
```

`schedule(runtime)` : on change d'ordonnancement avec `OMP_SCHEDULE`, sans recompiler.

| Variante | init | `OMP_SCHEDULE` | `OMP_PROC_BIND` | Temps (s) |
| --- | --- | --- | --- | --- |
| référence | par | `static` | `spread` | 0,9936 |
| init séquentielle | **seq** | `static` | `spread` | 0,9706 |
| cyclique | par | **`static,1`** | `spread` | **1,2995** |
| dynamique | par | **`dynamic`** | `spread` | 1,1023 |
| non attaché | par | `static` | **`false`** | 0,9739 |

Sur un seul nœud, « init séquentielle » ne change rien (un seul contrôleur) ; « cyclique » et « dynamique » restent nettement plus lents, car cet effet-là (localité de cache, surcoût d'ordonnancement) ne dépend pas du nombre de nœuds. La somme des $u_{i,j}$ affichée doit être **identique** dans les cinq cas.

> [!important] Les trois ingrédients — il les faut tous
> 1. une **initialisation parallèle** (first touch) ;
> 2. le **même découpage** des itérations à l'initialisation et au calcul ;
> 3. des threads **attachés**, qui ne quittent pas le nœud de leurs pages.
>
> Il suffit d'en retirer un pour perdre la localité.

## Tâches et NUMA

```c
#pragma omp parallel for schedule(static)                 // first touch
for (size_t i = 0; i < n; i++) a[i] = 0.0;

#pragma omp parallel masked taskloop grainsize(4096)
for (size_t i = 0; i < n; i++) a[i] = f(a[i]);            // qui touche quoi ?
```

Avec `for schedule(static)`, l'itération `i` revient toujours au même thread. Avec des [[Tâches OpenMP — dépendances et taskloop|tâches]], **n'importe quel thread libre** exécute la tâche : c'est ce qui équilibre la charge… et ce qui disperse les accès. Une partie des accès devient distante, comme la variante `dynamic` de Jacobi.

**Leviers :**

- la clause `affinity(a[i:g])` de `task` (5.0) : une **indication** « exécuter près de ces données ». Aucune garantie ; dans libgomp (gcc), acceptée mais **sans effet** ;
- garder l'ingrédient 3 : des threads attachés ;
- des tâches à **gros grain**, alignées sur les blocs de l'initialisation ;
- placer les données sans compter sur le premier accès : allocateurs OpenMP, ou `numactl --interleave` ;
- comme toujours : **mesurer**.

### Les allocateurs OpenMP (5.0)

Exprimer le placement **dans le code** plutôt que par le premier accès :

```c
omp_alloctrait_t traits[] = {{omp_atk_partition, omp_atv_interleaved}};
omp_allocator_handle_t alloc = omp_init_allocator(omp_default_mem_space, 1, traits);
double *t = omp_alloc(n * sizeof *t, alloc);
/* ... */
omp_free(t, alloc);
```

Trait `partition` : `environment` (défaut), `nearest`, `blocked`, `interleaved`. Le support réel varie selon les implémentations : à vérifier avant de compter dessus.

## Check-list NUMA

1. Combien de nœuds a ma machine ? (`numactl --hardware`, `lstopo`)
2. Mon code est-il limité par le débit mémoire ou par le calcul ?
3. Mes tableaux sont-ils initialisés **en parallèle** ?
4. Avec le **même `schedule`** que le calcul ?
5. Mes threads sont-ils **attachés** ? (`OMP_PLACES`, `OMP_PROC_BIND`)
6. L'ai-je **vérifié** ? (`OMP_DISPLAY_AFFINITY`)
7. `close` ou `spread` : l'ai-je **mesuré** ?
8. `numa_balancing` est-il actif pendant mes mesures ?
9. Des tâches ? Le first touch n'est plus garanti : mesurer.

## En TP — TP3, exercice 2

`TP/srcTP3/affinite.c` découpe un tableau en blocs contigus (512 Ko par défaut, autant de blocs que de threads) et fait 20 000 passes. Les versions ne diffèrent que par le thread qui traite chaque bloc à chaque passe :

- `static` vs `dynamic` sur des cœurs à L2 **privé** puis **partagé** ;
- `rotation` (à écrire) : à la passe $r$, le bloc $k$ va au thread $(k + r) \bmod p$ — chaque bloc change de cœur à chaque passe, ce qui mesure **le coût d'un changement de cœur** ;
- taille de bloc à partir de laquelle l'affinité cesse de compter → à relier aux tailles de cache ;
- cœurs rapides / lents (P-cores / E-cores, colonne `MAXMHZ` de `lscpu -e`) : avec `static`, le temps est fixé par le **plus lent**.

## Voir aussi

- [[NUMA et mémoire virtuelle]] — pages, MMU, first touch, `numactl`
- [[OPENMP#La clause `schedule`]] — les politiques de répartition
- [[Tâches OpenMP — dépendances et taskloop]] — pourquoi les tâches perdent le first touch
- [[Compiler, déboguer, mesurer]] — mesurer sans se mentir (placement non fixé = mesure fausse)

## Sources

- CM4, *Tâches (suite), NUMA et affinité mémoire* (`CM/openmp-numa-affinity-memoirevirtuelle.pdf`)
- TP3 OpenMP, *Graphes de tâches et localité* (`TP/tp3-OMP-taches.pdf`, sources `TP/srcTP3/`)
