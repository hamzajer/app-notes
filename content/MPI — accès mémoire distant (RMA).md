---
tags:
  - cours
  - parallelisme
  - mpi
  - hpc
up: "[[MPI]]"
date: 2026-10-16
status: à-réviser
source: "CM6 — CM2-MPI-CommCollectives.pdf"
---

# MPI — accès mémoire distant (RMA)

> [!abstract] En une phrase
> Avec les communications **à sens unique**, un processus expose une zone de sa mémoire (une **fenêtre**) et les autres y lisent ou y écrivent **seuls**, sans qu'il appelle MPI — en échange, il faut une **synchronisation explicite**, comme en mémoire partagée.

Suite de [[MPI]].

## Quand seul l'émetteur sait qu'il doit écrire

Avec `MPI_Send`/`MPI_Recv`, **les deux** processus participent : le récepteur doit savoir qu'un message arrive, et de qui. Or :

- dans le schéma [[MPI#Exemple du cours : maître et travailleurs|maître/travailleurs]], le maître ne fait que répondre à des demandes : il pourrait ne pas intervenir du tout ;
- dans un calcul **irrégulier**, un processus peut devoir mettre à jour une donnée d'un autre, sans que celui-ci sache quand ni combien de fois.

Avec le **RMA** (*Remote Memory Access*) :

- la **cible** expose une zone de sa mémoire, la **fenêtre** ;
- l'**origine** y lit ou y écrit **seule**, sans que la cible appelle MPI pour cette opération.

Si le réseau le permet (**RDMA**, *Remote Direct Memory Access*), la carte réseau de la cible écrit directement en mémoire, sans action du processeur.

## Créer une fenêtre

```c
MPI_Win win;
// exposer une zone déjà allouée : adresse, taille en OCTETS, unité de déplacement
MPI_Win_create(u, (n + 2) * sizeof *u, sizeof *u, MPI_INFO_NULL, MPI_COMM_WORLD, &win);
// ou laisser MPI allouer (mémoire éventuellement enregistrée auprès de la carte réseau)
MPI_Win_allocate(taille, sizeof(int), MPI_INFO_NULL, MPI_COMM_WORLD, &ptr, &win);
/* ... */
MPI_Win_free(&win);
```

- La création est **collective** sur le communicateur ; chacun expose sa propre zone, éventuellement **vide** (taille 0).
- Une cible est désignée par son **rang**, une position par un **déplacement** compté en unités depuis le début de la fenêtre de la cible.
- Variantes : `MPI_Win_allocate_shared` (mémoire réellement partagée entre processus d'un même nœud), `MPI_Win_create_dynamic` (zones attachées/détachées en cours d'exécution).

## Lire, écrire, combiner

| Opération | Effet sur la fenêtre de la cible |
| --- | --- |
| `MPI_Put` | écrire |
| `MPI_Get` | lire |
| `MPI_Accumulate` | combiner (`MPI_SUM`, `MPI_MAX`…, `MPI_REPLACE`) |
| `MPI_Get_accumulate` | lire l'ancienne valeur et combiner |
| `MPI_Fetch_and_op` | idem, pour **un seul** élément (plus rapide) |
| `MPI_Compare_and_swap` | remplacer si égal à une valeur attendue |

```c
MPI_Put(&u[n], 1, MPI_DOUBLE,          // données de l'origine
        droite, 0, 1, MPI_DOUBLE,      // cible : rang, déplacement, nombre, type
        win);
```

> [!warning] Comme un `MPI_Isend` : terminé seulement à la synchronisation suivante
> Avant elle, on ne lit pas le résultat d'un `MPI_Get`, et on ne modifie pas les données d'un `MPI_Put`.
> Deux `MPI_Put` sur le même élément dans la même **époque** (entre deux synchronisations) → résultat **non défini**. Les `MPI_Accumulate` sont **atomiques** élément par élément.

## Trois façons de synchroniser

### Active, collective : `MPI_Win_fence`

```c
for (int it = 0; it < ITER; it++) {
    MPI_Win_fence(0, win);                                                   // ouvre l'époque
    MPI_Put(&u[1], 1, MPI_DOUBLE, gauche, fantome_g, 1, MPI_DOUBLE, win);
    MPI_Put(&u[n], 1, MPI_DOUBLE, droite, 0,         1, MPI_DOUBLE, win);
    MPI_Win_fence(0, win);                                                   // les Put sont terminés partout
    /* calcul de v à partir de u, fantômes compris, puis copie dans u */
}
```

Collective sur la fenêtre : convient aux calculs **en phases** (calcul, puis échanges) — le modèle **BSP** (*Bulk Synchronous Parallel*).

### Active, entre quelques processus : *post-start-complete-wait*

```text
origine P0                                cible P1
                                          MPI_Win_post  (ouvre la fenêtre à un groupe)
MPI_Win_start  ◀──────── autorise ───────
  put ────────────────────────────────▶
  put ────────────────────────────────▶
MPI_Win_complete ──────── fini ─────────▶ MPI_Win_wait  (attend que les origines aient fini)
```

Seuls les processus concernés se synchronisent : pour des échanges entre **voisins**, c'est moins coûteux qu'un `fence` général.

### Passive : les verrous

`MPI_Win_lock` / `MPI_Win_unlock` sur un rang : la cible **ne participe pas**, elle calcule sans appeler MPI pour ces accès.

- `MPI_LOCK_EXCLUSIVE` pour un rédacteur seul, `MPI_LOCK_SHARED` pour plusieurs lecteurs ou des opérations atomiques ;
- à `MPI_Win_unlock`, les opérations sont **terminées** : un `MPI_Get` a rendu sa valeur ;
- `MPI_Win_lock_all` et `MPI_Win_flush` évitent de reprendre un verrou à chaque accès.

| Synchronisation | Qui participe | Usage typique |
| --- | --- | --- |
| `fence` | tous (collective) | phases calcul / échange (BSP) |
| post-start-complete-wait | origines et cibles concernées | échanges entre voisins |
| `lock` / `unlock` | l'origine seule | accès irréguliers, compteurs partagés |

## Exemple : distribuer des tâches sans maître

```c
constexpr int HOTE = 0;                       // rang qui héberge le compteur
int *compteur;                                // un entier sur HOTE, rien ailleurs
MPI_Win_allocate(r == HOTE ? sizeof(int) : 0, sizeof(int), MPI_INFO_NULL,
                 MPI_COMM_WORLD, &compteur, &win);
/* ... mise à zéro du compteur par HOTE, puis MPI_Barrier ... */

const int un = 1;
for (;;) {
    MPI_Win_lock(MPI_LOCK_SHARED, HOTE, 0, win);
    MPI_Fetch_and_op(&un, &t, MPI_INT, HOTE, 0, MPI_SUM, win);   // t = compteur++ atomiquement
    MPI_Win_unlock(HOTE, win);                                    // ici, t est valide
    if (t >= NB_TACHES) break;
    local += calcul(t);
}
MPI_Reduce(&local, &total, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);
```

La répartition reste **dynamique**, comme avec le maître, mais P0 ne fait qu'**héberger** le compteur : il calcule comme les autres. C'est l'analogue de `schedule(dynamic)` et de son compteur atomique en [[OPENMP#La clause `schedule`|OpenMP]] — ou du [[OPENMP#Le cas qui la rend nécessaire : le task-farm|task-farm]] protégé par `critical`.

> [!example] Vérifié — Open MPI 4.1.6, 4 processus, 1000 tâches
> ```text
> rang 0 : 227 taches
> rang 1 : 272 taches
> rang 2 : 271 taches
> rang 3 : 230 taches
> total = 499500 (attendu 499500)
> ```
> Chaque tâche est prise exactement une fois ; la répartition varie d'une exécution à l'autre. (`constexpr` est du C23 : avec un compilateur plus ancien, `#define HOTE 0`.)

## Voir aussi

- [[MPI]] — point à point, collectives, choisir sa communication
- [[MPI — communicateurs et topologies]]
- [[Mémoire partagée vs mémoire distribuée]] — le RMA rapproche la mémoire distribuée de la mémoire partagée, avec ses problèmes de synchronisation

## Sources

- CM6, *MPI : communications non bloquantes, collectives et communicateurs* (`CM/CM2-MPI-CommCollectives.pdf`), partie « Communications à sens unique »
- Exemple du compteur compilé et exécuté avec Open MPI 4.1.6 (`mpicc -O2`, `mpirun -np 4`)
