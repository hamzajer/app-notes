---
tags:
  - cours
  - parallelisme
  - architecture
  - memoire
up: "[[APP — MOC]]"
date: 2026-09-11
updated: 2026-10-16
---

# Localité et caches

Les performances sont liées aux **caches**, à tous les niveaux. C'est la conséquence directe du [[Le mur de la puissance#Vitesse de communication interne|coût de déplacement de l'information]] : meilleures latences, RAM 10 ns, réseau 1 µs, SSD 30 µs, disque 4 ms — soit, rapporté au cycle (~0,3 ns), de quelques dizaines de milliers à plusieurs millions d'opérations perdues en attendant une donnée. Depuis la fin du siècle dernier, le goulot n'est plus le calcul, c'est **le transfert des données**.

## Les deux localités

Les calculs doivent être organisés pour favoriser :

- la localité **spatiale** — utiliser des données proches en mémoire ;
- la localité **temporelle** — réutiliser vite une donnée déjà chargée.

Concrètement, pour un tableau `T[]`, `T[i+1]` doit être manipulé **juste après** `T[i]`, et **par la même unité de calcul**.

> [!warning] C'est le contraire du parallélisme !
> La localité veut **regrouper** sur le même cœur ; le parallélisme veut **répartir** sur des cœurs différents. Toute parallélisation est un compromis entre les deux.

## La ligne de cache

Le cache ne travaille ni à l'octet ni au mot, mais par **lignes** de 64 ou 128 octets : lire un `double` en charge 7 (ou 15) voisins.

**Cohérence de cache (protocole MESI & co.)** : chaque cœur a son L1. Une ligne est soit **partagée en lecture** par plusieurs caches, soit **détenue en écriture exclusive** par un seul. Chaque écriture **invalide** les copies des autres.

```bash
getconf LEVEL1_DCACHE_LINESIZE      # taille de ligne annoncée
lscpu ; lstopo                      # tailles et partage des caches (lstopo : paquet hwloc)
```

## Conséquence pratique : découper par blocs

```text
❌ entrelacé (round-robin)              ✅ par blocs contigus
T : [0][1][2][3][4][5][6][7]           T : [0][1][2][3][4][5][6][7]
     A  B  A  B  A  B  A  B                 A  A  A  A  B  B  B  B
     └── même ligne de cache ──┘            └── A ──┘ └── B ──┘
     → les 2 cœurs se la disputent          → une ligne, un cœur
```

Découper un tableau entre threads **par blocs contigus** plutôt qu'en alternance : sinon les cœurs se disputent les mêmes lignes de cache, chaque écriture invalide le cache du voisin. C'est le ***false sharing***. En OpenMP, c'est la différence entre `schedule(static)` et `schedule(static, 1)` (voir [[OPENMP#La clause `schedule`]]).

## Le faux partage

> [!example] L'expérience du CM2
> Deux threads, deux compteurs **logiquement indépendants**, aucun partage de donnée. Chacun incrémente le sien 50 000 000 fois ; on fait varier l'écart entre les deux compteurs dans un tableau de `long long`.
>
> | Écart (mots) | 0 | 1 | 2 | 3 | **4** | 6 | 8 | 16 | 32 |
> | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
> | Écart (octets) | 0 | 8 | 16 | 24 | **32** | 48 | 64 | 128 | 256 |
> | Temps (s) | 1,276 | 1,378 | 1,167 | 1,197 | **0,227** | 0,227 | 0,226 | 0,226 | 0,227 |
>
> Intel Core Ultra 5 228V, médiane de 7 exécutions. Le résultat est **juste dans tous les cas** ; seul le temps change, d'un facteur **5**.

Tant que les deux compteurs sont dans la même ligne, chaque incrément invalide la ligne chez l'autre : elle fait la navette à chaque tour. **Les données ne sont pas partagées, la ligne l'est.**

> [!warning] Le piège est invisible dans le code
> Les deux threads écrivent dans des cases **différentes** : aucune [[Parallélisme C++#Data race|data race]], le résultat est correct. Seule la performance s'effondre. Voir [[Parallélisme C++#Mesurer le temps|comment mesurer l'effet]].

**Deux leçons :**

1. **Concevoir ses structures en tenant compte de la ligne.** Un accumulateur par thread dans un tableau ? Les espacer (*padding*) — ou mieux, une variable locale et une [[OPENMP#La réduction|réduction]].
2. **La mesure contredit la documentation.** Transition mesurée ici à **32 octets**, alors que `getconf LEVEL1_DCACHE_LINESIZE` annonce 64. La granularité de cohérence effective varie d'une machine à l'autre : ne pas la déduire d'une fiche technique, **la mesurer**.

> [!note] Le pire cas : `atomic` sur une seule variable
> Dans l'[[OPENMP#Étude de cas : π en quatre versions|étude de cas π]], un `atomic` à chaque itération fait faire la navette à **une** ligne entre 8 cœurs : 132× plus lent que le séquentiel.

## Un mot sur SIMD

Il existe du parallélisme **à l'intérieur d'un cœur** : une instruction SIMD applique la même opération à 4, 8 ou 16 valeurs. Facteur 4 à 16, sans thread, sans synchronisation, sans accès concurrent — et le compilateur sait souvent le faire seul (`-O3`). C'est le **premier** parallélisme à aller chercher, parce que c'est le moins cher (voir [[Compiler, déboguer, mesurer#Ce que le compilateur fait déjà]]).

## Au-delà du cache : la mémoire non uniforme

Sur une machine à plusieurs sockets, la mémoire elle-même est découpée en **nœuds NUMA** : l'unité de placement n'est plus la ligne mais la **page** (4 Kio). *La page est au placement NUMA ce que la ligne est au cache.* Voir [[NUMA et mémoire virtuelle]] et [[Affinité et placement des threads]].

## Voir aussi

- [[Le mur de la puissance]] — pourquoi la mémoire doit être proche
- [[Accélération et efficacité]] — les défauts de cache sont l'une des fuites d'efficacité ; ils expliquent aussi le speedup super-linéaire
- [[NUMA et mémoire virtuelle]] — la même logique à l'échelle de la page et du nœud mémoire
- TP3 OpenMP, exercice « Placer les threads près de leurs données » (`TP/tp3-OMP-taches.pdf`, `TP/srcTP3/affinite.c`)
