---
tags:
  - cours
  - parallelisme
  - architecture
  - mpi
up: "[[APP — MOC]]"
date: 2026-10-13
status: à-réviser
updated: 2026-10-16
---

# Mémoire partagée vs mémoire distribuée

> [!abstract] En une phrase
> En mémoire partagée, les threads **lisent la même mémoire** et se synchronisent. En mémoire distribuée, chaque processus a **sa propre mémoire** et rien ne circule sans un **message explicite**.

## Les deux architectures

```text
        MÉMOIRE PARTAGÉE                          MÉMOIRE DISTRIBUÉE
   (un nœud, plusieurs cœurs)               (plusieurs nœuds reliés par un réseau)

  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐       ┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐
  │ C0  │ │ C1  │ │ C2  │ │ C3  │       │ P0  │   │ P1  │   │ P2  │   │ P3  │
  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘       ├─────┤   ├─────┤   ├─────┤   ├─────┤
     └───────┴───┬───┴───────┘          │ mém │   │ mém │   │ mém │   │ mém │
         ┌───────┴───────┐              └──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
         │ mémoire commune│                 └────────┴───┬────┴─────────┘
         └───────────────┘                        ═══ réseau ═══
   x écrit par C0 → visible par C3         x de P0 n'existe pas pour P3
```

Un supercalculateur est **les deux à la fois** : chaque nœud est à mémoire partagée (des dizaines de cœurs), et les milliers de nœuds sont reliés par un réseau (voir [[Machines de calcul — TOP500 et BOINC|El Capitan et son réseau Slingshot]]). D'où la programmation **hybride** : MPI entre les nœuds, [[OPENMP]] ou des threads dans chaque nœud.

> [!note] Nuance : partagée, mais pas uniforme
> Sur un nœud moderne à plusieurs sockets, la mémoire est partagée mais **NUMA** : tous les cœurs lisent toute la mémoire, mais pas au même prix. Voir [[NUMA et mémoire virtuelle]]. En hybride, on met souvent **un processus MPI par nœud NUMA** et des threads OpenMP à l'intérieur.

## Comparaison

| | Mémoire partagée | Mémoire distribuée |
| --- | --- | --- |
| Unité d'exécution | thread | processus |
| Espace d'adressage | **commun** | **un par processus** |
| Échange de données | lecture/écriture d'une variable | **message** explicite (envoi + réception) |
| Danger principal | [[Parallélisme C++#Data race\|data race]] | **interblocage** (deadlock) sur les messages |
| Synchronisation | `mutex`, `atomic`, barrière | implicite : recevoir = attendre l'envoi |
| Passage à l'échelle | limité à un nœud (dizaines de cœurs) | jusqu'à des millions de cœurs |
| Outils | [[Parallélisme C++\|std::thread]], [[OPENMP]] | [[MPI]] |
| Coût d'un échange | accès mémoire (ns) | traversée du réseau (µs) |

> [!tip] La data race disparaît, le deadlock arrive
> Aucune variable n'est partagée, donc aucune course aux données possible. En échange, deux processus qui s'attendent mutuellement bloquent pour toujours. Voir [[MPI#Le piège : l'interblocage]].

## Le modèle SPMD

*Single Program, Multiple Data* : on lance **le même programme** $p$ fois, et chaque copie se distingue par son **rang** $r \in \{0, \dots, p-1\}$.

```c
if (rank == 0) { /* lire l'entrée, distribuer */ }
/* tout le monde : calculer sur SON morceau de données */
if (rank == 0) { /* rassembler, écrire le résultat */ }
```

C'est le rang qui décide **quelles données** traiter et **avec qui** communiquer. Le parallélisme est entièrement **explicite** : rien n'est réparti automatiquement.

## Le coût d'un message

Le modèle classique (Hockney) découpe le temps d'envoi de $n$ octets en deux termes :

$$T(n) = \alpha + \frac{n}{\beta}$$

| Terme | Nom | Ce qui le fixe |
| --- | --- | --- |
| $\alpha$ | **latence** | coût fixe de *chaque* message : logiciel, carte réseau, aller-retour |
| $\beta$ | **bande passante** | débit du lien (octets/s) |

> [!warning] Conséquence : grouper les messages
> 1 000 messages de 1 octet paient $1000\,\alpha$ ; un message de 1 000 octets paie $\alpha$ une seule fois. Valeurs mesurées de $\alpha$ et $\beta$ : [[Latence et débit — de l'horloge au réseau#Ping-pong MPI mesuré|ping-pong MPI]]. Même logique que la [[Tâches OpenMP — exemple Fibonacci#2. Le problème : trop de tâches|granularité des tâches]] : un coût fixe par unité de travail impose de grosses unités.

## Décomposition de domaine

La manière standard de paralléliser un calcul sur une grille : chaque processus reçoit **un bloc contigu** du domaine (même raison que pour la [[Localité et caches|localité]]).

Problème : un calcul local (ex. stencil `u[i] = (u[i-1] + u[i+1]) / 2`) a besoin des cases **du voisin** au bord du bloc. On ajoute donc des **cellules fantômes** (*ghost cells*, *halo*) remplies par message à chaque itération.

```text
          P0                     P1                     P2
  ┌───┬───┬───┬───┬───┐  ┌───┬───┬───┬───┬───┐  ┌───┬───┬───┬───┬───┐
  │   │ ■ │ ■ │ ■ │ g │  │ g │ ■ │ ■ │ ■ │ g │  │ g │ ■ │ ■ │ ■ │   │
  └───┴───┴───┴─┬─┴─▲─┘  └─▲─┴─┬─┴───┴─┬─┴─▲─┘  └─▲─┴─┬─┴───┴───┴───┘
                │   └──────┼───┘       │   └──────┼───┘
                └──────────┘           └──────────┘
        ■ = cases possédées    g = copie fantôme de la case du voisin
```

À chaque pas de temps : **1.** échange des halos → **2.** calcul local, sans aucune communication.

> [!note] Rapport surface / volume
> Le calcul croît comme le **volume** du bloc, la communication comme sa **surface**. Plus les blocs sont gros, plus la communication devient négligeable : c'est pourquoi MPI passe bien à l'échelle sur de gros problèmes, et mal sur de petits.

## Voir aussi

- [[MPI]] — l'outil standard de la mémoire distribuée
- [[Parallélisme, asynchronisme, concurrence]] — en mémoire distribuée, la concurrence sur la mémoire disparaît
- [[Accélération et efficacité]] — la communication est une fuite d'efficacité de plus

## Sources

- LLNL, *[Message Passing Interface (MPI)](https://hpc-tutorials.llnl.gov/mpi/what_is_mpi/)* — modèle à mémoire distribuée, parallélisme explicite
- GeeksforGeeks, *[Shared Memory Model vs Message Passing Model](https://www.geeksforgeeks.org/computer-organization-architecture/difference-between-shared-memory-model-and-message-passing-model-in-ipc/)* — comparaison des deux modèles (à l'échelle d'une machine)
