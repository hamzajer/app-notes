---
tags:
  - cours
  - parallelisme
  - mpi
  - openmp
  - hpc
up: "[[APP — MOC]]"
date: 2026-11-09
status: à-réviser
source: "TP du 06/11 — tp3-MPI-OMP.pdf (N. Maillard, G. Mounié, N. du Pasquier)"
---

# MPI — programmation hybride avec OpenMP

> [!abstract] En une phrase
> Pour occuper tous les cœurs d'un ensemble de machines, on peut lancer un processus [[MPI]] par cœur, ou moins de processus ayant chacun plusieurs threads [[OPENMP]] : le partage du travail se joue alors à deux niveaux, et le placement fait partie du programme.

> [!info] D'où vient cette note
> Le site n'annonce pas de CM sur ce thème : tout part du TP du 06/11 (`TP/tp3-MPI-OMP.pdf`, sources `TP/srcTP-MPI-OMP-3/`). Les réponses aux questions sont des prévisions tant qu'elles n'ont pas été mesurées en salle, sur 4 machines ; les mesures ci-dessous viennent d'**une seule** machine.

## Placer processus et threads

Une exécution hybride se décrit par le nombre de processus par machine et le nombre $t$ de threads par processus :

```bash
mpirun --hostfile listemachines.txt --map-by ppr:2:node:PE=3 \
       -x OMP_NUM_THREADS=3 ./mandel blocs
```

| Élément | Rôle |
| --- | --- |
| `ppr:2:node` | 2 processus par machine, soit 8 sur 4 machines |
| `PE=3` | réserve 3 cœurs à chaque processus, car `mpirun` attache les processus à des cœurs |
| `-x OMP_NUM_THREADS=3` | transmet la variable aux processus lancés sur les **autres** machines |
| `-x OMP_SCHEDULE` | pareil pour l'ordonnancement des boucles `schedule(runtime)` |

Les exemples de l'énoncé sont écrits pour 6 cœurs : `nproc` donne le vrai nombre, et les machines d'une même salle ne sont pas toutes identiques.

> [!danger] Un oubli ne provoque aucune erreur
> Sans `PE=`, les threads d'un processus risquent de se partager un seul cœur ; sans `-x`, les autres machines gardent leur nombre de threads par défaut. Le programme se termine normalement, seulement plus lentement. `verifier_placement`, dans le code fourni, affiche `ATTENTION` s'il repère plus de threads que de cœurs autorisés ou des nombres de threads différents selon les processus.

> [!example] Mesuré — `mandel cyclique`, 2 processus × 2 threads, 4 cœurs physiques
> | Options de `mpirun` | Attachement (`--report-bindings`) | Temps |
> | --- | --- | --- |
> | `--map-by ppr:2:node:PE=2` | chaque processus sur 2 cœurs | 2,04 s |
> | `--map-by ppr:2:node --bind-to core` | chaque processus sur 1 cœur | 2,95 s |

## Déclarer les threads à MPI

Un processus qui utilise des threads remplace `MPI_Init` par :

```c
int MPI_Init_thread(int *argc, char ***argv, int demande, int *fourni);
```

| Niveau (du plus faible au plus fort) | Ce que le programme s'engage à respecter |
| --- | --- |
| `MPI_THREAD_SINGLE` | un seul thread s'exécute |
| `MPI_THREAD_FUNNELED` | plusieurs threads, mais seul le thread principal appelle MPI |
| `MPI_THREAD_SERIALIZED` | tout thread peut appeler MPI, jamais deux en même temps |
| `MPI_THREAD_MULTIPLE` | tout thread peut appeler MPI, à tout moment |

`fourni` peut être **inférieur** à `demande` : il faut le vérifier, comme le fait `main` dans `jacobi.c` et `mandel.c`.

## Mandelbrot : un calcul irrégulier

Pour chaque pixel $c$ : $z_0 = 0$, $z_{k+1} = z_k^2 + c$, jusqu'à $|z_k| > 2$ ou `iter_max` itérations. Une ligne coûte de $n$ à $n \times$ `iter_max` itérations, et aucune ligne n'a besoin des autres : toute la difficulté est d'équilibrer.

| Version | Répartition entre processus |
| --- | --- |
| `omp` | un seul processus |
| `blocs` | une bande de lignes consécutives par processus |
| `cyclique` | paquets de `paquet` lignes (8 par défaut), le paquet $b$ au processus $b \bmod p$ |

Entre les threads d'un processus, c'est `schedule(runtime)`, réglé par `OMP_SCHEDULE`. La racine rassemble l'image par `MPI_Gatherv`, et le témoin doit être le même pour toutes les versions.

> [!example] Mesuré — une machine, 4 cœurs physiques, `n = 2048`, `iter_max = 5000`
> | Version | $p \times t$ | `OMP_SCHEDULE` | Temps (s) | `calcul_min` | `calcul_max` |
> | --- | --- | --- | --- | --- | --- |
> | `omp` | 1 × 4 | `static` | 3,71 | | |
> | `omp` | 1 × 4 | `dynamic,4` | 2,21 | | |
> | `blocs` | 2 × 2 | `static` | 3,87 | 3,84 | 3,87 |
> | `blocs` | 2 × 2 | `dynamic,4` | 2,22 | 2,19 | 2,21 |
> | `blocs` | 4 × 1 | `static` | 5,01 | **0,006** | **5,00** |
> | `cyclique` | 4 × 1 | `static` | 2,45 | 2,33 | 2,44 |
>
> Le même témoin pour toutes (`7ba4d3e236fb375a`). Les temps varient d'environ 20 % d'une exécution à l'autre sur ce portable ; l'écart entre `calcul_min` et `calcul_max`, lui, est net.

Ce qu'on lit dans ce tableau :

- **Entre threads**, `static` donne à certains threads les lignes chères : `dynamic` récupère l'écart (Q2.1, et les images montrent qui a calculé quoi).
- **Avec 4 bandes**, les deux bandes extrêmes contiennent presque aucun point de l'ensemble, qui tient dans $|\mathrm{Im}\, c| \lesssim 1{,}12$ : deux processus font tout le travail.
- **Avec 2 bandes**, l'équilibre vient de la symétrie de l'image par rapport à l'axe réel. C'est un hasard de $p = 2$, qui n'existe plus dès qu'on a 4 machines.
- `dynamic` entre threads **ne déplace pas de travail d'un processus à l'autre**.

Prévision pour la Q2.2, sur 4 machines : `blocs` laisse environ la moitié des processus presque oisifs quelle que soit la répartition, puisqu'il y a au moins 4 bandes. `cyclique` équilibre dès la répartition entre processus, et supporte donc bien un processus par cœur.

## Jacobi : une version hybride

Chaque point intérieur prend la moyenne de ses 4 voisins, $v_{i,j} = \frac{1}{4}(u_{i-1,j} + u_{i+1,j} + u_{i,j-1} + u_{i,j+1})$. Les lignes sont réparties par bandes, et chaque processus garde en **fantômes** une ligne de chaque voisin (voir [[MPI#Exemple du cours : cellules fantômes en 1D|les fantômes en 1D]]). Calcul régulier, mais échanges à chaque itération.

Question 3.1, dans `jacobi.c` :

```c
int it;
P->ecart = INFINITY;
for (it = 0; it < iter_max && P->ecart > eps; it++) {
    echanger_fantomes(P);                                  // hors région parallèle
    double local = 0.0;
#pragma omp parallel for schedule(static) reduction(max : local)
    for (int i = 1; i <= P->nloc; i++) {
        double e = moyenne_ligne(P, i);
        local = e > local ? e : local;
    }
    P->ecart = ecart_global(P, local);                     // hors région parallèle
    echanger_tableaux(P);
}
return it;
```

Niveau à demander : **`MPI_THREAD_FUNNELED`**, à inscrire dans le tableau `versions` en bas du fichier, où la ligne `hybride` est livrée avec `MPI_THREAD_SINGLE`. Plusieurs threads existent, et seul le thread principal appelle MPI, puisque les communications sont entre les régions parallèles.

Le **témoin** résume la plaque au bit près : il valide la version, quels que soient $p$ et $t$.

> [!example] Vérifié — `n = 2048`, 500 itérations, une machine
> `omp` à 1, 2 et 4 threads, `mpi` à 4 processus, `hybride` en 1 × 4, 2 × 2 et 4 × 1 donnent tous le témoin `31ea8c698c103313`. Les temps, eux, ne disent rien ici : 4,8 s à 1 thread et entre 3,7 et 6,1 s à 4 threads selon l'exécution. Pour conclure, il faut mesurer en salle.

Sur le réseau, le découpage en bandes a une conséquence simple. Avec des rangs consécutifs sur chaque machine (`ppr:k:node`), seules $M - 1$ frontières sur $M$ machines traversent le réseau, **quel que soit** le nombre de processus par machine. L'hybride supprime donc les échanges internes à une machine, sans réduire le trafic réseau. La colonne `comm(s)` permet de vérifier ce que ces échanges coûtaient. Avec `--map-by node`, au contraire, toutes les frontières passent par le réseau.

## Pièges

| Oubli | Symptôme | Correction |
| --- | --- | --- |
| `PE=` absent | threads entassés sur un cœur, lenteur sans erreur | `--map-by ppr:k:node:PE=t` |
| `-x OMP_NUM_THREADS` absent | nombre de threads différent selon les machines | le transmettre, et lire les `ATTENTION` |
| `-x OMP_SCHEDULE` absent | `schedule(runtime)` différent selon les machines | le transmettre aussi |
| `MPI_THREAD_SINGLE` laissé avec des threads | programme non conforme, même s'il semble marcher | demander `MPI_THREAD_FUNNELED` et vérifier `fourni` |
| Regarder seulement le temps total | déséquilibre invisible | comparer `calcul_min` et `calcul_max` |
| Plus de threads que de cœurs de la machine | temps dégradés | relever `nproc` sur **chaque** machine |

## Voir aussi

- [[MPI]] — préparation des machines, placement, fantômes, `Allreduce`
- [[OPENMP#La clause `schedule`]] — `static`, `dynamic`, `runtime`
- [[Affinité et placement des threads]] — `OMP_PLACES`, `OMP_PROC_BIND`, le placement côté OpenMP
- [[NUMA et mémoire virtuelle]] — pourquoi un processus par nœud NUMA est un choix courant
- [[Mémoire partagée vs mémoire distribuée]] — un supercalculateur est les deux à la fois

## Sources

- TP MPI 3, *Programmation hybride MPI + OpenMP* (`TP/tp3-MPI-OMP.pdf`, `TP/srcTP-MPI-OMP-3/`) — N. Maillard, G. Mounié, N. du Pasquier
- Mesures : Open MPI 4.1.6, `mpicc -O3 -fopenmp`, une machine à 4 cœurs physiques (i5-8265U), TODO complétés sur une copie
