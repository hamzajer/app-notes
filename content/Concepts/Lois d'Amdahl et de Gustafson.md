---
tags:
  - cours
  - parallelisme
  - performance
up: "[[APP — MOC]]"
date: 2026-10-16
status: à-réviser
source: "CM2 — cours2-slides.pdf"
---

# Lois d'Amdahl et de Gustafson

> [!abstract] En une phrase
> Amdahl répond à « combien de temps vais-je gagner sur **ce** problème ? » (plafond $1/\alpha$) ; Gustafson à « quel problème plus **gros** vais-je pouvoir traiter dans le même temps ? » (pas de plafond). Les deux sont exactes : elles ne posent pas la même question.

Les métriques de base ($S_m$, $E_m$) sont dans [[Accélération et efficacité]].

## La loi d'Amdahl (1967)

Soit $\alpha$ la fraction **purement séquentielle** du travail : $\alpha T_1$ est incompressible, $(1-\alpha) T_1$ est parfaitement parallélisable.

$$T_m = \alpha T_1 + \frac{(1-\alpha)\,T_1}{m} \qquad\Longrightarrow\qquad S_m = \frac{1}{\alpha + \frac{1-\alpha}{m}} \xrightarrow[m \to \infty]{} \frac{1}{\alpha}$$

```text
m = 1   │██ séq ██│░░░░░░░░ travail parallélisable ░░░░░░░░│   T1 = 10
m = 4   │██ séq ██│░░│                                         T4 = 4
m → ∞   │██ séq ██│                                           T∞ = α·T1 = 2  →  S_max = 1/α = 5
        └─ cette frontière ne bouge jamais ─┘
```

| $\alpha$ | $S_{16}$ | $S_{64}$ | $S_{256}$ | $S_{1024}$ | $S_\infty$ |
| --- | --- | --- | --- | --- | --- |
| 50 % | 1,9 | 2,0 | 2,0 | 2,0 | **2** |
| 10 % | 6,4 | 8,8 | 9,7 | 9,9 | **10** |
| 5 % | 9,1 | 15,4 | 18,6 | 19,6 | **20** |
| 1 % | 13,9 | 39,3 | 72,1 | 91,2 | **100** |
| 0,1 % | 15,8 | 60,2 | 204,0 | 506,2 | **1000** |

Avec 5 % de séquentiel : **jamais plus de 20**, quel que soit l'argent investi. Prise au pied de la lettre, cette loi condamne le calcul parallèle à grande échelle.

### Discussion : $\alpha$ n'est pas une constante

Le point faible est de supposer $\alpha$ fixe, indépendant de la **taille du problème**. En réalité :

- la partie séquentielle (initialisations, E/S, coordination) croît lentement avec la taille — disons $O(N)$ ;
- la partie parallélisable croît vite — disons $O(N^3)$ ;
- donc **quand $N$ augmente, $\alpha$ diminue**.

Et surtout : personne n'achète une machine mille fois plus grosse pour résoudre le même problème mille fois plus vite. On l'achète pour résoudre un problème **mille fois plus gros**.

## La loi de Gustafson-Barsis (1988)

On renverse la question : on **fixe le temps** acceptable, et on fait croître la machine et le problème ensemble. Soit $\alpha$ la fraction du temps **parallèle** (normalisé à 1) passée en séquentiel. Le même travail en séquentiel prendrait $\alpha + n(1-\alpha)$, d'où l'**accélération à l'échelle** (*scaled speedup*) :

$$S_n = \alpha + n(1 - \alpha) = n - \alpha\,(n - 1)$$

Linéaire en $n$, de pente $(1-\alpha)$ : **plus de plafond**. Avec 5 % de séquentiel et 1024 processeurs : Amdahl promet **19,6**, Gustafson **973**.

## Les deux lois côte à côte

```text
        AMDAHL : le problème est fixé              GUSTAFSON : le temps est fixé
m = 1   │█│░░░░│               T1 = 5        m = 1   │█│░░░░│                T1 = 5
m = 4   │█│░│                  T4 = 2        m = 4   │█│░░░░│ ×4 de travail  T4 = 5
        S4 = 5/2 = 2,5                              S4 = 17/5 = 3,4
        plafonné à 1/α = 5                          S_m = m − α(m − 1), sans plafond
```

Même $\alpha$, même $m$, deux réponses : 2,5 et 3,4. Ce ne sont pas les mêmes questions.

| | Amdahl | Gustafson |
| --- | --- | --- |
| Question | « J'achète plus de cœurs : combien de **temps** je gagne ? » | « J'achète plus de cœurs : quel **problème** je peux traiter ? » |
| Ce qui est fixe | la taille du problème | le travail **par processeur** |
| Nom | **scalabilité forte** (*strong scaling*) | **scalabilité faible** (*weak scaling*) |
| Réponse | décourageante, et juste | encourageante, et juste aussi |

> [!tip] En pratique
> On mesure et on présente **les deux**. La forte s'effondre toujours ; la faible reste plate bien plus longtemps. Un article qui ne montre que la faible cache quelque chose.

## Mesurer α : la métrique de Karp-Flatt

En pratique on ne connaît pas $\alpha$, on connaît des **temps**. On retourne donc l'équation d'Amdahl pour obtenir la **fraction séquentielle expérimentale** (Karp & Flatt, 1990) :

$$e = \frac{\dfrac{1}{S_n} - \dfrac{1}{n}}{1 - \dfrac{1}{n}}$$

L'intérêt n'est pas la valeur de $e$, mais **son évolution avec $n$** :

- $e$ **constant** ⇒ Amdahl s'applique : une vraie fraction séquentielle, à chercher dans le code ;
- $e$ **croissant** ⇒ ce n'est pas du code séquentiel mais un **surcoût qui augmente avec le nombre de threads** : synchronisations, contention, déséquilibre de charge, hétérogénéité du matériel.

> [!example] Karp-Flatt sur des mesures réelles (CM2)
> | $p$ | $T_p$ (s) | $S_p$ | $E_p$ | $e$ |
> | --- | --- | --- | --- | --- |
> | 1 | 0,0800 | 1,00 | 1,00 | — |
> | 2 | 0,0400 | 2,00 | 1,00 | 0,000 |
> | 3 | 0,0280 | 2,86 | 0,95 | 0,025 |
> | 4 | 0,0250 | 3,20 | 0,80 | 0,083 |
> | 5 | 0,0230 | 3,48 | 0,70 | 0,109 |
> | 6 | 0,0200 | 4,00 | 0,67 | 0,100 |
> | 7 | 0,0170 | 4,71 | 0,67 | 0,081 |
> | 8 | 0,0150 | 5,33 | 0,67 | 0,071 |
>
> $E_p$ plafonne dès $p = 6$ : il dit **que** ça se dégrade. $e$ croît nettement jusqu'à $p = 5$, signe d'un surcoût croissant (synchronisation, contention) : il dit **pourquoi**. C'est pour ça qu'on calcule Karp-Flatt.

Vérification pour $p = 4$ : $e = (1/3{,}2 - 1/4)/(1 - 1/4) = 0{,}0625/0{,}75 \approx 0{,}083$.

## Voir aussi

- [[Accélération et efficacité]] — $S_m$, $E_m$, speedup absolu ou relatif, super-linéarité
- [[Ordonnancement et théorème de Graham]] — l'autre borne : $T_m \ge \max(W/m,\ CP)$
- [[Compiler, déboguer, mesurer]] — obtenir des temps fiables avant de les interpréter
- [[OPENMP#Étude de cas : π en quatre versions]] — un cas concret où l'on mesure

## Sources

- CM2, *Les concepts du parallélisme — OpenMP*, partie « Que peut-on espérer ? » (`CM/cours2-slides.pdf`)
- G. Amdahl, AFIPS 1967 — J. Gustafson, *Reevaluating Amdahl's Law*, CACM 31(5), 1988 — A. Karp & H. Flatt, CACM 33(5), 1990
