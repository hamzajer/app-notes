---
tags:
  - cours
  - parallelisme
  - performance
  - outils
up: "[[APP — MOC]]"
date: 2026-10-16
status: à-réviser
source: "CM2 — cours2-slides.pdf"
---

# Compiler, déboguer, mesurer

> [!abstract] Le cycle
> Analyser → implanter → déboguer → mesurer → recommencer. Le parallélisme n'est qu'**une** des optimisations possibles, et ce n'est ni la première ni la moins chère.

## La règle d'or

> [!important] On ne parallélise qu'un code séquentiel **correct** et **déjà optimisé**
> 1. c'est le **code de référence** : il dit si la version parallèle calcule juste ;
> 2. c'est le $T_1$ : sans lui, pas d'[[Accélération et efficacité|accélération]] claire ;
> 3. paralléliser un code lent donne un code lent sur $n$ cœurs. Un facteur 3 gagné par la [[Localité et caches|localité]] coûte moins cher qu'un facteur 3 acheté avec 8 cœurs.

## Ce que le compilateur fait déjà

| Option | Effet |
| --- | --- |
| `-O0` (défaut) | rien : c'est le mode **débogage** |
| `-O2` | le niveau raisonnable |
| `-O3` | ajoute la **vectorisation** (SIMD) |

> [!danger] Mesurer du `-O0` n'a aucun sens
> C'est l'erreur la plus fréquente en TP : elle produit de magnifiques accélérations qui disparaissent en `-O2`.

### Le piège `-ffast-math`

Cette option autorise le compilateur à traiter l'addition flottante comme **associative**, ce qui lui permet de vectoriser les réductions. Mais en IEEE 754, $(a + b) + c \ne a + (b + c)$ en général : les résultats changent, parfois beaucoup.

C'est **exactement** le problème d'une réduction parallèle : elle ne donne pas le même résultat que le séquentiel, ni le même d'une exécution à l'autre si le nombre de threads change. Ce n'est pas un bug — mais on ne valide pas une parallélisation avec `diff` sur des flottants (voir [[OPENMP#La réduction]]).

## La boîte à outils

| Outil | Pour quoi | Surcoût |
| --- | --- | --- |
| `gdb` | débogage classique ; `-g`, combinable avec `-O2` | — |
| `valgrind` | accès mémoire invalides, fuites | ×10 à 50 |
| `-fsanitize=address,undefined` | mémoire, comportements indéfinis | faible |
| **`-fsanitize=thread`** | **accès concurrents** (data race) | ×5 à 15 |

```bash
gcc -g -fsanitize=address,undefined code.c          # mémoire, UB
gcc -g -fopenmp -fsanitize=thread code.c            # accès concurrents
```

> [!tip] ThreadSanitizer est l'outil de cette UE
> Il instrumente les accès et signale toute **data race** — deux threads, même adresse, au moins une écriture, pas de synchronisation — avec **les deux piles d'appel** fautives.

## Profiler

```bash
perf stat ./code                      # cycles, IPC, défauts de cache
perf record ./code && perf report     # où passe le temps
hyperfine ./v1 ./v2                   # mesure correcte : répétitions, écart-type
```

`perf stat` donne en une commande les **instructions par cycle** et le **taux d'échec des caches** : de quoi savoir tout de suite si on est limité par le calcul ou par la mémoire.

## Mesurer sans se mentir

| Erreur | Pourquoi c'est faux | Correction |
| --- | --- | --- |
| Mesurer une fois | variabilité courante de 10 % | ≥ 30 exécutions, **médiane** et dispersion |
| Oublier l'échauffement | la 1ʳᵉ exécution paie les défauts de page et la montée en fréquence | la jeter |
| Ignorer la fréquence variable | 1 cœur seul va plus vite que 8 chargés | en tenir compte : ça dégrade mécaniquement les accélérations |
| Problème trop petit | s'il tient en L2, on ne mesure pas ce qu'on croit ; s'il dure quelques ms, on mesure la création des threads | grossir le problème |
| Placement non fixé | l'OS déplace les threads | `OMP_PROC_BIND`, `OMP_PLACES` — voir [[Affinité et placement des threads]] |
| Chronométrer autre chose | `clock()` = temps CPU **cumulé** (augmente avec les threads) ; `gettimeofday()` obsolète et peut reculer | `omp_get_wtime()`, ou `clock_gettime(CLOCK_MONOTONIC)` hors OpenMP — voir [[Parallélisme C++#Mesurer le temps]] |

## Limité par le calcul ou par la mémoire ?

**Intensité arithmétique** = opérations flottantes par octet chargé.

| Noyau | Intensité | Conséquence |
| --- | --- | --- |
| Produit scalaire | 2 flops / 16 octets = **0,125** | limité par la **mémoire** : ajouter des cœurs n'ajoute pas de bande passante, ça plafonne très tôt |
| Triade `a[i] = b[i] + s*c[i]` | 2 flops / 24 octets | idem — c'est le noyau de STREAM, voir [[Affinité et placement des threads#La triade]] |
| Produit de matrices | $O(N^3)$ opérations sur $O(N^2)$ données : croît avec $N$ | limité par le **calcul** : s'accélère très bien |

> [!warning] Avant de s'acharner sur une accélération décevante
> Vérifier qu'on n'a pas déjà **saturé la bande passante mémoire**. Dans ce cas, la seule issue est algorithmique — pas d'ajouter des threads. Sur une machine NUMA, la bande passante se multiplie avec le nombre de contrôleurs mémoire **utilisés** : voir [[NUMA et mémoire virtuelle]].

## Voir aussi

- [[Accélération et efficacité]] · [[Lois d'Amdahl et de Gustafson]] — interpréter les temps mesurés
- [[OPENMP#Check-list]] — la check-list complète avant de présenter une mesure
- [[Latence et débit — de l'horloge au réseau]] — les ordres de grandeur

## Sources

- CM2, *Les concepts du parallélisme — OpenMP*, partie « Compiler, déboguer, profiler » (`CM/cours2-slides.pdf`)
