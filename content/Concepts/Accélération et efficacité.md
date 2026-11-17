---
tags:
  - cours
  - parallelisme
  - performance
up: "[[APP — MOC]]"
date: 2026-09-11
updated: 2026-10-16
---

# Accélération et efficacité

Les deux métriques qui disent si paralléliser a servi à quelque chose.

$$S_m = \frac{T_1}{T_m} \qquad\qquad E_m = \frac{S_m}{m} = \frac{T_1}{m \, T_m}$$

| Symbole | Nom | Définition |
| --- | --- | --- |
| $T_1$ | temps séquentiel | temps du programme sur 1 cœur |
| $T_m$ | temps parallèle | temps du programme sur $m$ cœurs |
| $S_m$ | **accélération** (*speedup*) | combien de fois on va plus vite |
| $E_m$ | **efficacité** | accélération rapportée au nombre de cœurs, entre 0 et 1 |

Lecture :

- $S_m = m$ et $E_m = 1$ → accélération **linéaire**, cas idéal : chaque cœur ajouté est pleinement utilisé.
- $E_m < 1$ → cas réel : une partie du temps est perdue en synchronisation, communication et parties séquentielles.
- $E_m$ décroît quand $m$ augmente : c'est ce qui limite le **passage à l'échelle**.

```text
S_m ↑
    │          ╭──────────  idéal : S_m = m
  8 │        ╱ ╭─────
    │      ╱ ╭─
  4 │    ╱ ╭─╯      réel : E_m se dégrade
    │  ╱ ╭─╯
  2 │ ╱╭─╯
  1 │╱╯
    └────┴────┴────┴────→ m
    1    2    4    8
```

> [!warning] Speedup absolu ou relatif ? Le dire.
> « Meilleur » $T_1$ = celui du **meilleur code séquentiel connu**.
> - **Relatif** : la version parallèle comparée à elle-même sur 1 thread. Flatteur, car ce $T_1$ contient déjà tous les surcoûts de parallélisation.
> - **Absolu** : comparée au meilleur séquentiel. C'est le seul honnête.

> [!note] $S_m > m$ est possible : l'accélération super-linéaire
> Dans le monde réel on s'attend à $T_m \ge T_1/m$, donc $S_m \le m$. Mais deux causes courantes donnent $S_m > m$ :
> - **effets de cache** : $m$ fois plus de cœurs, c'est aussi $m$ fois plus de cache L1/L2 ; le sous-problème d'un thread peut y tenir alors que le problème entier n'y tenait pas ;
> - **changement d'ordre des opérations** : une recherche parallèle peut tomber plus tôt sur la solution.
>
> Ni erreur de mesure, ni exploit : à expliquer.

> [!example] Une accélération peut être un gâchis
> $S = 40$ sur 1000 cœurs, c'est une accélération… et une efficacité de 4 %.

> [!warning] Où part l'efficacité perdue
> Attente sur les verrous ([[Parallélisme C++#Mutex et `condition_variable`|`mutex`, `condition_variable`]]), défauts de cache dus à une mauvaise [[Localité et caches|localité]], et fraction du code restée séquentielle. Le [[Ordonnancement et théorème de Graham#Théorème de Graham|théorème de Graham]] borne, lui, la perte due au seul ordonnancement.

Ce qu'on peut espérer au mieux, selon que la taille du problème est fixe ou non : [[Lois d'Amdahl et de Gustafson]]. Pour savoir **pourquoi** $E_m$ se dégrade : la métrique de [[Lois d'Amdahl et de Gustafson#Mesurer α : la métrique de Karp-Flatt|Karp-Flatt]].

## Voir aussi

- [[Lois d'Amdahl et de Gustafson]] — le plafond $1/\alpha$, la scalabilité forte et faible, Karp-Flatt
- [[Compiler, déboguer, mesurer]] — mesurer $T_1$ et $T_m$ sans se mentir
- [[Ordonnancement et théorème de Graham]] — la borne théorique sur la perte
- [[Parallélisme C++#Mesurer le temps]] — comment obtenir $T_1$ et $T_m$ en pratique
