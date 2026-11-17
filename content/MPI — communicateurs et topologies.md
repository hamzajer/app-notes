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

# MPI — communicateurs et topologies

> [!abstract] En une phrase
> Un communicateur choisit **qui** participe à une communication : on découpe `MPI_COMM_WORLD` en lignes, colonnes ou nœuds pour faire des collectives sur un sous-ensemble, et on raisonne en coordonnées de grille plutôt qu'en rangs.

Suite de [[MPI]] (point à point, collectives).

## Qu'est-ce qu'un communicateur ?

Un communicateur réunit :

- un **groupe** : un ensemble **ordonné** de processus, numérotés de $0$ à $p-1$ — le rang d'un processus **dépend du communicateur** ;
- un **contexte** : un message envoyé dans un communicateur ne peut être reçu **que** dans ce communicateur.

Deux usages :

1. faire opérer une collective sur un **sous-ensemble** : une ligne, une colonne, les processus d'un même nœud… ;
2. **isoler** les messages d'une bibliothèque de ceux de l'application, même si leurs étiquettes coïncident :
   ```c
   MPI_Comm comm_biblio;
   MPI_Comm_dup(MPI_COMM_WORLD, &comm_biblio);   // mêmes processus, contexte neuf
   ```

Prédéfinis : `MPI_COMM_WORLD` (tous), `MPI_COMM_SELF` (soi seul). Les autres se créent par union ou division, et se libèrent par `MPI_Comm_free`.

## Découper : `MPI_Comm_split`

```c
MPI_Comm ligne;
MPI_Comm_split(MPI_COMM_WORLD, r / q, r % q, &ligne);   // (couleur, clé)
MPI_Bcast(x, nb, MPI_DOUBLE, 0, ligne);                  // diffusion dans MA ligne seulement
```

C'est une **collective** : chaque processus donne une **couleur** et une **clé**. Ceux de même couleur forment un nouveau communicateur, où ils sont numérotés selon la clé.

```text
grille 4 × 4 (rang r)      couleur = r / 4 → lignes        couleur = r % 4 → colonnes
 0  1  2  3                [ 0  1  2  3]  ligne 0          colonne 0 : 0, 4,  8, 12
 4  5  6  7                [ 4  5  6  7]  ligne 1          colonne 1 : 1, 5,  9, 13
 8  9 10 11                [ 8  9 10 11]  ligne 2          colonne 2 : 2, 6, 10, 14
12 13 14 15                [12 13 14 15]  ligne 3          colonne 3 : 3, 7, 11, 15
```

- Couleur `MPI_UNDEFINED` : le processus reçoit `MPI_COMM_NULL` (il ne fait partie d'aucun nouveau communicateur).
- `MPI_Comm_split_type(..., MPI_COMM_TYPE_SHARED, ...)` regroupe les processus d'un **même nœud** : c'est la base du MPI + OpenMP hybride.

> [!example] Vérifié — Open MPI 4.1.6, 8 processus, $q = 4$
> ```text
> world 0..3 → ligne 0, rangs 0..3 dans la ligne
> world 4..7 → ligne 1, rangs 0..3 dans la ligne
> MPI_Bcast(x, ..., 0, ligne) : la ligne 0 reçoit la valeur du rang 0, la ligne 1 celle du rang 4
> ```

## Les topologies cartésiennes

```c
int dims[2] = {0, 0}, periodes[2] = {0, 0}, coords[2];
MPI_Dims_create(p, 2, dims);                                  // p = dims[0] × dims[1], équilibré
MPI_Comm grille;
MPI_Cart_create(MPI_COMM_WORLD, 2, dims, periodes, 1, &grille);   // 1 : renumérotation autorisée
MPI_Comm_rank(grille, &r);
MPI_Cart_coords(grille, r, 2, coords);                        // rang → (ligne, colonne)

int haut, bas;
MPI_Cart_shift(grille, 0, 1, &haut, &bas);                    // voisins dans la dimension 0

int garder[2] = {0, 1};
MPI_Comm ligne;
MPI_Cart_sub(grille, garder, &ligne);                         // même découpage que Comm_split
```

| Fonction | Rôle |
| --- | --- |
| `MPI_Dims_create` | factorise $p$ en une grille équilibrée (`dims` à 0 = « à choisir ») |
| `MPI_Cart_create` | crée le communicateur-grille ; `periodes[d] = 1` → dimension **torique** |
| `MPI_Cart_coords` / `MPI_Cart_rank` | rang ↔ coordonnées |
| `MPI_Cart_shift` | rangs des voisins dans une dimension |
| `MPI_Cart_sub` | sous-grilles (lignes, colonnes…) |

- Au bord d'une dimension non périodique, `MPI_Cart_shift` rend **`MPI_PROC_NULL`** : l'échange de fantômes s'écrit sans cas particulier (voir [[MPI#Exemple du cours : cellules fantômes en 1D]]).
- Avec la renumérotation autorisée, la bibliothèque peut placer les voisins de la grille sur des nœuds **proches** dans le réseau.

> [!example] Vérifié — 8 processus
> `MPI_Dims_create(8, 2, dims)` donne une grille **4 × 2**. Le processus (0, 0) a `haut = MPI_PROC_NULL` (−2 sous Open MPI) et `bas = 2` ; le processus (3, 1) a `haut = 5` et `bas = MPI_PROC_NULL`.

## Exemple : produit matrice-vecteur sur une grille $q \times q$

Le processus $(i, j)$ possède le bloc $A_{ij}$ ; le bloc $x_j$ n'est connu que de $(j, j)$ ; on veut $y_i = \sum_j A_{ij} x_j$ sur $(i, i)$.

```c
MPI_Cart_create(MPI_COMM_WORLD, 2, dims, periodes, 1, &grille);
MPI_Cart_coords(grille, r, 2, coords);
int i = coords[0], j = coords[1];
MPI_Comm_split(grille, i, j, &ligne);        // dans ligne, mon rang est j
MPI_Comm_split(grille, j, i, &colonne);      // dans colonne, mon rang est i

MPI_Bcast(x, B, MPI_DOUBLE, j, colonne);     // (j,j) diffuse x_j dans la colonne j
produit_local(a, x, y_partiel);              // A_ij x_j
MPI_Reduce(y_partiel, y, B, MPI_DOUBLE, MPI_SUM, i, ligne);   // somme sur (i,i)
```

```mermaid
graph LR
    D["(j,j) détient x_j"] -- "Bcast dans la colonne j" --> C["(0..q-1, j)<br/>reçoivent x_j"]
    C -- "A_ij · x_j en local" --> P["y partiels"]
    P -- "Reduce dans la ligne i" --> Y(["(i,i) détient y_i"])
    classDef c fill:#dce9f7,stroke:#3b6ea5,color:#12263a
    classDef r fill:#e2f0e4,stroke:#4a8a5c,color:#122a18
    class D,C,P c
    class Y r
```

Une diffusion par colonne puis une réduction par ligne : $q$ de chaque, **simultanées**, sur $q$ processus chacune. Coût : $O(\log q)$ étapes au lieu de $O(\log p)$, avec des messages de taille $n/q$.

## Voir aussi

- [[MPI]] — point à point, non bloquant, collectives
- [[MPI — accès mémoire distant (RMA)]] — les fenêtres se créent aussi sur un communicateur
- [[Mémoire partagée vs mémoire distribuée#Décomposition de domaine]] — pourquoi une grille de processus

## Sources

- CM6, *MPI : communications non bloquantes, collectives et communicateurs* (`CM/CM2-MPI-CommCollectives.pdf`), partie « Communicateurs et topologies »
- Exemples `Comm_split` / `Cart_create` compilés et exécutés avec Open MPI 4.1.6 (`mpirun --oversubscribe -np 8`)
