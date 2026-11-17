---
tags:
  - cours
  - parallelisme
  - architecture
  - memoire
  - numa
up: "[[APP — MOC]]"
date: 2026-10-16
status: à-réviser
source: "CM4 — openmp-numa-affinity-memoirevirtuelle.pdf (N. Maillard)"
---

# NUMA et mémoire virtuelle

> [!abstract] En une phrase
> Sur un nœud moderne, la mémoire est **partagée mais pas uniforme** : chaque groupe de cœurs a sa mémoire locale, et c'est **le premier thread qui touche une page** qui décide où elle sera — pas `malloc`.

La suite côté programmation (attacher les threads, mesurer) est dans [[Affinité et placement des threads]].

## De UMA à NUMA

**UMA** (*Uniform Memory Access*) : tous les cœurs passent par **le même contrôleur mémoire**. Même latence pour tous, simple à programmer. Mais la bande passante du contrôleur est partagée : ajouter des cœurs n'ajoute pas de débit mémoire, et au-delà de quelques cœurs le contrôleur devient le goulot.

Idée : donner à **chaque groupe de cœurs son contrôleur et sa mémoire**. Tous les cœurs lisent toute la mémoire, mais pas au même prix.

```text
        nœud 0                                      nœud 1
  ┌──────────────────────┐                  ┌──────────────────────┐
  │ c0   c1   c2   c3    │                  │ c4   c5   c6   c7    │
  │   cache L3 partagé   │◀═══ lien ═══════▶│   cache L3 partagé   │
  │ contrôleur mémoire   │   UPI (Intel)    │ contrôleur mémoire   │
  └──────────┬───────────┘ Infinity Fabric  └──────────┬───────────┘
     DRAM locale au nœud 0      (AMD)          DRAM locale au nœud 1
```

- Chaque nœud a sa mémoire **locale** ; celle des autres nœuds est **distante** : un accès distant traverse le lien.
- La mémoire reste **partagée** : un seul espace d'adressage, cohérent — on parle de **ccNUMA** (*cache-coherent NUMA*).
- Un nœud n'est pas forcément un socket (modes Intel SNC, AMD NPS).

### Ce que coûte le distant

| Effet | Conséquence |
| --- | --- |
| **Latence** | chaque accès distant est plus lent |
| **Débit** | si toutes les données sont sur un seul nœud, **un seul contrôleur travaille**, quel que soit le nombre de threads |

> [!important] Le débit est souvent le plus coûteux
> Pour un code parallèle, ce n'est pas la latence d'un accès distant qui fait mal, c'est d'avoir laissé tous les contrôleurs sauf un au repos.

## Lire sa machine

```bash
lscpu | grep -i numa          # nombre de nœuds, cœurs de chacun
numactl --hardware            # nœuds, mémoire libre, distances
lstopo                        # dessin de la topologie (paquet hwloc)
lstopo --no-io topo.pdf       # ... en PDF
```

```text
$ numactl --hardware                 # machine du cours : 1 seul nœud
available: 1 nodes (0)
node 0 cpus: 0 1 2 3 4 5 6 7
node 0 size: 31577 MB
node distances:
node   0
  0:  10
```

**La table des distances** vient du micrologiciel (table ACPI SLIT). Convention : **10** = accès local ; les autres valeurs sont **relatives** (20 ≈ « deux fois plus cher »). Ce ne sont pas des nanosecondes, elles sont indicatives : seule la mesure fait foi. Sur 4 nœuds ou plus, la matrice n'est pas forcément uniforme.

Ma machine (i5-8265U, 4 cœurs / 8 threads) est dans le même cas : `available: 1 nodes (0)`, distance `10`.

> [!warning] Sur un portable, on ne voit rien
> Avec un seul nœud NUMA, il n'y a qu'un contrôleur : les colonnes « distant » et « entrelacé » sont vides, et les effets de first touch ne se mesurent pas. Les chiffres du cours ont été pris sur une telle machine — les effets attendus sont décrits, pas observés.

## Adresses virtuelles, pages physiques

Le processus voit une mémoire :

- **immense** : $2^{47}$ octets d'adresses sur x86-64 (128 Tio), bien plus que la RAM ;
- **isolée** : il ne voit pas la mémoire des autres processus ;
- **disponible à la demande** : `malloc` réussit même pour plus que ce qui est libre.

Ces adresses sont **virtuelles** : elles ne disent rien de l'endroit où sont physiquement les octets. En NUMA, une question de plus : **dans quelle RAM** ?

### La MMU traduit, page par page

- La mémoire est découpée en **pages** : 4 Kio sur x86-64, 16 Kio sous macOS/Apple Silicon (`getconf PAGESIZE`).
- La **MMU** (*Memory Management Unit*) traduit adresse virtuelle → adresse physique grâce à la **table des pages** tenue par le système.
- Les traductions récentes sont gardées dans un cache dédié : la **TLB**.

> [!tip] La page est au placement NUMA ce que la ligne est au cache
> Une page est **entièrement** sur un nœud. C'est l'unité de placement, comme la [[Localité et caches#La ligne de cache|ligne de cache]] est l'unité de cohérence.

### `malloc` n'alloue rien

`malloc(1 << 30)` réserve 1 Gio **d'adresses**, pas de mémoire physique : la table des pages est vide pour ces adresses. Au **premier accès** à une page :

1. la MMU ne trouve pas de traduction : **défaut de page** ;
2. le noyau choisit une page physique libre, **sur un nœud qu'il choisit** ;
3. il complète la table des pages, et l'instruction reprend.

C'est l'**allocation paresseuse**. Reste à savoir sur quel nœud.

## La politique first touch

> [!important] Le premier accès décide
> Par défaut, Linux place la page sur le **nœud du cœur qui a provoqué le défaut de page** (politique `MPOL_DEFAULT`, `man 2 set_mempolicy`).
> - Ce n'est pas `malloc` qui décide, c'est le **premier accès**.
> - Le thread qui **initialise** un tableau décide de son placement pour toute la suite du programme.
> - Initialisation **séquentielle** ⇒ tout le tableau sur **un seul nœud**.
> - Une page reste où elle est placée : elle ne suit pas le thread qui l'utilise ensuite.

> [!example] Exemple 1 du cours : où sont mes pages ?
> On alloue un tableau, on l'initialise de quatre façons, puis on demande au noyau le nœud de chaque page avec l'appel système `move_pages` (sans nœud destination : il ne déplace rien).
>
> | Mode | Pages présentes | Placement attendu en NUMA |
> | --- | --- | --- |
> | `malloc` seul | **0 %** | rien : aucune page physique |
> | `calloc` | **0 %** | rien non plus : pour les gros blocs, la glibc sait que les pages neuves sont déjà nulles et ne les touche pas |
> | init séquentielle | 100 % | tout sur le nœud du thread principal |
> | init `parallel for schedule(static)` | 100 % | réparti comme les itérations |

Dans une boucle parallèle, c'est la clause [[OPENMP#La clause `schedule`|`schedule`]] qui dit quel thread touche quelle page en premier. `static` est déterministe : c'est pour ça qu'une initialisation parallèle place les pages de façon **prévisible**.

## D'autres politiques de placement

First touch est le défaut ; on peut en imposer d'autres **sans recompiler** :

```bash
numactl --interleave=all ./prog      # pages réparties à tour de rôle sur tous les nœuds
numactl --membind=1 ./prog           # uniquement sur le nœud 1
numactl --preferred=1 ./prog         # nœud 1 si possible
numactl --cpunodebind=0 ./prog       # threads sur le nœud 0
```

Dans le code : `set_mempolicy`, `mbind` (libnuma, `numaif.h`), ou les [[Affinité et placement des threads#Les allocateurs OpenMP (5.0)|allocateurs OpenMP]].

`--interleave` : aucun accès n'est tout à fait local, mais **tous les contrôleurs travaillent**. Utile quand on ne peut pas modifier le code.

## L'OS doit aussi placer les threads

L'ordonnanceur du système arbitre entre deux besoins contraires :

- les **caches** : ne pas déplacer les threads, qui retrouvent leurs données dans le cache du cœur ;
- le **parallélisme** : déplacer les threads pour équilibrer la charge.

En NUMA, un thread déplacé vers un autre nœud **laisse ses pages derrière lui** : tous ses accès deviennent distants. ⇒ Pour un code de calcul, on **attache** chaque thread à un cœur ou à un groupe de cœurs : voir [[Affinité et placement des threads]].

### Et si le noyau migrait les pages ?

**Automatic NUMA balancing** : Linux échantillonne les accès et peut migrer une page vers le nœud qui l'utilise le plus (`cat /proc/sys/kernel/numa_balancing`, 1 = actif). Utile pour des programmes mal placés, mais la migration coûte (copie, invalidation de TLB), elle réagit **après coup**, et elle **brouille les mesures**. Pour mesurer l'effet du first touch seul : `sudo sysctl kernel.numa_balancing=0`.

## Voir aussi

- [[Affinité et placement des threads]] — `OMP_PLACES`, `OMP_PROC_BIND`, la triade, Jacobi 2D, la check-list NUMA
- [[Localité et caches]] — la même logique à l'échelle de la ligne
- [[Mémoire partagée vs mémoire distribuée]] — NUMA est entre les deux : partagée, mais avec une notion de distance
- [[MPI — programmation hybride avec OpenMP]] — en hybride, souvent un processus MPI par nœud NUMA

## Sources

- CM4, *Tâches (suite), NUMA et affinité mémoire* (`CM/openmp-numa-affinity-memoirevirtuelle.pdf`)
- `man 2 set_mempolicy`, `man 2 move_pages`, `man 8 numactl`
