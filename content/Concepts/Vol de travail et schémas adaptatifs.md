---
tags:
  - cours
  - parallelisme
  - ordonnancement
  - vol-de-travail
up: "[[APP — MOC]]"
date: 2026-11-13
status: à-réviser
---

# Vol de travail et schémas adaptatifs

> [!abstract] En une phrase
> Au lieu d'une file centrale de tâches (le **partage de travail**), chaque cœur a **sa propre pile de tâches** et ne va **voler** chez un autre que lorsqu'il n'a plus rien. Résultat mathématique : $T_p \le W/p + O(CP)$ en espérance, avec seulement $O(p \cdot CP)$ vols — on garde la garantie de [[Ordonnancement et théorème de Graham|Graham]] **sans** liste centrale.

CM du 13/11 — *Tâches et ordonnancement II*. Notations du cours : $W$ = travail ($T_1$), $CP$ = chemin critique ($T_\infty$), $p$ processeurs.

> [!warning] Note reconstruite sans les diapositives
> Le support de ce CM n'est pas en ligne. La note s'appuie sur les articles d'origine (Blumofe–Leiserson, Cilk-5, équipe MOAIS de Grenoble — voir [[#Sources]]) et sur deux expériences faites sur ce portable. Les points où le vocabulaire du prof est incertain sont signalés.

---

## 1. Partage ou vol de travail

Le CM2 l'annonçait : la *task-farm* (un indice ou une file **partagée**, chacun se sert quand il a fini) équilibre la charge, mais **la centralisation devient un goulot**.

```text
     PARTAGE DE TRAVAIL (work sharing)              VOL DE TRAVAIL (work stealing)

            ┌──────────────────┐                  P0 ┌──┬──┬──┐   P1 ┌──┐    P2 ┌──┬──┐
            │   file centrale  │ ◀── tout           │t1│t4│t7│      │t2│       │t3│t6│
            └──┬────┬────┬───┬─┘     passe ici      └──┴──┴─▲┘      └─▲┘       └──┴──┘
     dépose/   │    │    │   │                            │ push/pop  │           ▲
     retire    ▼    ▼    ▼   ▼                            │ en BAS    │           │ vol en HAUT
              P0   P1   P2   P3                           P0          P1       P3 (oisif)
   → chaque tâche créée migre                → on ne migre une tâche que si un cœur est oisif
```

| | Partage de travail | Vol de travail |
| --- | --- | --- |
| Qui prend l'initiative ? | le **producteur** dépose ses nouvelles tâches dans le pool | le **cœur oisif** va chercher du travail |
| Structure | une file **centrale**, protégée par un verrou | une **deque** par cœur |
| Migrations de tâches | **toutes** les tâches | seulement quand quelqu'un est oisif |
| Quand tout le monde a du travail | on continue de migrer | **aucune** communication |
| Localité | une tâche part sur n'importe quel cœur | un cœur exécute surtout **ses** tâches, dans l'ordre séquentiel |

> [!quote] Blumofe & Leiserson (1999)
> « *Quand tous les processeurs ont du travail, un ordonnanceur à vol de travail ne migre aucune tâche, alors qu'un ordonnanceur à partage de travail en migre toujours.* »

### L'algorithme

Chaque cœur traite sa deque **comme une pile d'appels** :

1. **Création** d'une tâche (`spawn`, `#pragma omp task`, `go f()`) : on la pose **en bas** de sa propre deque.
2. **Tâche suivante** : on la reprend **en bas** — c'est la plus récente, ordre **LIFO**, comme l'exécution séquentielle.
3. **Deque vide** : le cœur devient **voleur**. Il choisit une **victime au hasard** et lui prend la tâche **du haut**, la plus **ancienne**.

> [!tip] Pourquoi voler la plus ancienne ?
> Dans une récursion (fibo, tri fusion…), la tâche la plus ancienne est la plus **proche de la racine**, donc celle qui contient **le plus de travail**. Un seul vol rapporte un gros morceau, et le voleur n'aura pas à revoler de sitôt. Le propriétaire, lui, travaille en profondeur d'abord sur des données encore chaudes en [[Localité et caches|cache]].

---

## 2. Le résultat mathématique

> [!important] Théorème (Blumofe & Leiserson, JACM 1999)
> Pour un calcul *fully strict* (chaque tâche ne se synchronise qu'avec son parent — c'est le cas de `spawn`/`sync`, `task`/`taskwait`) de travail $W$ et de chemin critique $CP$, le vol de travail **aléatoire** sur $p$ processeurs vérifie :
> $$\mathbb{E}[T_p] \;\le\; \frac{W}{p} + O(CP)$$
> - nombre **espéré** d'essais de vol : $O(p \cdot CP)$ ;
> - avec probabilité $\ge 1-\varepsilon$ : $T_p \le W/p + O(CP + \log p + \log 1/\varepsilon)$ ;
> - **mémoire** : $S_p \le p \cdot S_1$ ($S_1$ = mémoire de l'exécution séquentielle) ;
> - **communication** espérée : $O(p \cdot CP \cdot (1 + n_d) \cdot S_{max})$.
>
> Les trois bornes sont optimales à une constante près.

C'est la même forme que [[Ordonnancement et théorème de Graham|Graham]] ($T \le W/m + CP$), mais **sans liste centrale** : la garantie est obtenue de façon **distribuée**, et la communication est **comptée**.

### La preuve en une idée : des jetons dans deux seaux

À chaque pas de temps, chacun des $p$ processeurs dépose **un jeton** :

```text
                  à chaque pas, chaque processeur fait UNE chose
                 ┌───────────────────────┴───────────────────────┐
           il exécute une instruction                  il tente un vol
                     │                                       │
             ┌───────▼───────┐                       ┌───────▼───────┐
             │  seau TRAVAIL │                       │   seau VOL    │
             │   total = W   │                       │ total = nb de │
             │  (exactement) │                       │ tentatives    │
             └───────────────┘                       └───────────────┘
                     p · T_p  =  W  +  (nombre de tentatives de vol)
```

$$T_p = \frac{W + \text{tentatives}}{p} \qquad\text{et}\qquad \mathbb{E}[\text{tentatives}] = O(p \cdot CP) \quad\Longrightarrow\quad \mathbb{E}[T_p] = \frac{W}{p} + O(CP)$$

Tout le travail de la preuve est de borner le seau VOL. **L'intuition** (la preuve complète suit, avec le [[#Le potentiel de deque (Arora, Blumofe, Plaxton)|potentiel de deque]]) : la tâche du chemin critique qui attend d'être exécutée se trouve toujours **en haut** d'une deque (c'est la plus ancienne). Une tentative de vol tombe sur cette deque avec probabilité $1/p$. En moyenne, toutes les $\sim p$ tentatives, l'une d'elles fait donc **avancer le chemin critique d'un cran**. Le chemin critique n'a que $CP$ crans, d'où $O(p \cdot CP)$ tentatives.

### Le potentiel de deque (Arora, Blumofe, Plaxton)

C'est l'outil qui rend la preuve rigoureuse : il **borne le seau VOL**. On attache à chaque nœud prêt une énergie, le **potentiel**, qui ne peut que diminuer, et on montre que chaque série de $p$ tentatives de vol en détruit une fraction constante.

**Poids et potentiel d'un nœud.** Soit $d(u)$ la profondeur de $u$ dans l'arbre d'activation (son « parent désigné » est le nœud dont l'exécution l'a rendu prêt) :

$$w(u) = CP - d(u) \qquad\qquad \varphi(u) = \begin{cases} 3^{2w(u)} & \text{si } u \text{ attend dans une deque} \\ 3^{2w(u)-1} & \text{si } u \text{ est en cours d'exécution} \end{cases}$$

Le potentiel total $\Phi$ est la somme sur tous les nœuds prêts ou en cours. Au départ, seule la racine existe, en cours d'exécution, de poids $CP$ : $\Phi_0 = 3^{2CP-1}$. À la fin, plus aucun nœud : $\Phi = 0$.

> [!tip] Le chemin critique est caché dans l'exposant
> $\log_3 \Phi_0 = 2\,CP - 1$. Si chaque phase de vols détruit une **fraction constante** de $\Phi$, il faut $O(\log \Phi_0) = O(CP)$ phases pour arriver à 0. Toute la preuve tient dans cette remarque.

#### 1. Le potentiel ne fait que baisser

Seuls deux événements le modifient, et les deux le font baisser :

| Événement | Avant | Après | Baisse |
| --- | --- | --- | --- |
| **vol** du nœud du haut $u$ (poids $w$) | $3^{2w}$ (dans la deque) | $3^{2w-1}$ (en cours chez le voleur) | $\frac{2}{3}\,\varphi(u)$ |
| **exécution** de $u$, qui active 2 enfants de poids $w-1$ | $3^{2w-1}$ | $3^{2w-2} + 3^{2w-3} = \frac{4}{9}\,3^{2w-1}$ (un empilé, un exécuté) | $\ge \frac{5}{9}\,\varphi(u)$ |

C'est pour ces deux lignes qu'on a choisi $3^{2w}$ et le « $-1$ » : un nœud **en cours** vaut 3 fois moins qu'un nœud **en attente** (donc un vol fait baisser $\Phi$), et deux enfants valent ensemble moins que leur parent (donc l'exécution aussi).

#### 2. Lemme structurel : les poids décroissent vers le bas

> [!important] Lemme structurel
> Dans toute deque, les parents désignés des nœuds, lus **du haut vers le bas**, sont sur un **même chemin** racine → feuille de l'arbre d'activation, et sont distincts (sauf éventuellement ceux du nœud du bas et du nœud en cours).
> **Conséquence** : les poids sont **strictement décroissants du haut vers le bas** de la deque.

Ce que ça donne sur une vraie deque, relevée au pas 400 de la simulation (fib(22), $p = 4$, processeur P0) :

```text
          poids w     potentiel φ = 3^(2w)        part du potentiel de la deque
  HAUT ─▶   40       ███████████████████████████   88,9 %   ← un voleur prend celui-ci
            39       ███                           9,9 %
            38       ▏                             1,1 %
            37       ▏                             0,1 %
            ⋮                                       …
  BAS  ─▶   28       ▏                             ≈ 0
  en cours  25       ▏  (3^(2w−1))                 ≈ 0
```

Chaque niveau pèse au moins **9 fois moins** que celui du dessus ($3^{2(w-1)} = 3^{2w}/9$).

#### 3. Lemme des deques « lourdes en haut »

> [!important] *Top-Heavy Deques*
> Pour toute deque non vide, le nœud du **haut** porte au moins **3/4** du potentiel de son processeur (deque + nœud en cours).

Preuve : les autres nœuds sont en progression géométrique de raison $\le 1/9$. Le pire cas est une deque à **un seul** nœud de poids $w$, avec un nœud en cours de même poids : $\frac{3^{2w}}{3^{2w} + 3^{2w-1}} = \frac{1}{1 + 1/3} = \frac{3}{4}$.

**Conséquence** : un vol qui tombe sur une deque non vide prend le nœud du haut et lui fait perdre $2/3$ de son potentiel, donc détruit au moins $\frac{2}{3} \times \frac{3}{4} = \frac{1}{2}$ du potentiel de cette victime.

#### 4. Les phases et les boules dans des urnes

On découpe l'exécution en **phases** d'environ $p$ tentatives de vol. Chaque tentative vise une victime **au hasard** : c'est un lancer de boules dans des urnes, chaque urne (processeur) étant pondérée par son potentiel.

> [!important] Lemme des boules et des urnes pondérées
> On lance $p$ boules au hasard dans $p$ urnes de poids $W_1, \dots, W_p$, de somme $W$. Soit $X$ le poids total des urnes touchées. Pour tout $\beta \in (0, 1)$ :
> $$\Pr[X \ge \beta W] \;>\; 1 - \frac{1}{(1-\beta)\,e}$$

Avec $\beta = 1/2$ : avec probabilité $> 1 - 2/e \approx 0{,}26 > 1/4$, les vols d'une phase touchent des processeurs portant **la moitié** du potentiel, et chacun en perd la moitié. Les processeurs à deque vide, eux, exécutent leur nœud en cours et perdent $5/9$ de son potentiel. Au total :

$$\Pr\big[\text{la phase fait baisser } \Phi \text{ d'au moins } 1/4\big] \;\ge\; \frac{1}{4}$$

#### 5. Le compte final

```text
   Φ₀ = 3^(2·CP − 1)  ──(× 3/4 par phase réussie)──▶  Φ < 1  ⟹  Φ = 0  (Φ est entier)

   phases réussies nécessaires  ≤  (2·CP − 1) · log_{4/3}(3)  ≈  7,6 · CP
   une phase réussit avec probabilité ≥ 1/4  ⟹  phases espérées ≤ 4 × 7,6 · CP  =  O(CP)
   chaque phase = p tentatives de vol         ⟹  tentatives espérées  =  O(p · CP)
```

D'où, avec les jetons : $\mathbb{E}[T_p] = \dfrac{W + O(p \cdot CP)}{p} = \dfrac{W}{p} + O(CP)$.

> [!note] Bonus : la version « machine partagée »
> L'article d'Arora, Blumofe et Plaxton (1998) fait la preuve avec une deque **non bloquante** et un système d'exploitation **adversaire**, qui ne donne au calcul que $p_A$ processeurs en moyenne : $\mathbb{E}[T] = O\!\left(\dfrac{W}{p_A} + CP \cdot \dfrac{p}{p_A}\right)$. Accélération linéaire tant que $p$ reste petit devant le parallélisme $W/CP$.

#### Les lemmes vérifiés par simulation

Le potentiel est calculé exactement (entiers de Python) à chaque pas, sur fib(22) ($CP = 43$), 3 tirages par valeur de $p$ :

| $p$ | hausses de $\Phi$ | deques mal ordonnées | part **minimale** du haut | phases réussies |
| ---: | ---: | ---: | ---: | ---: |
| 2 | 0 | 0 | 0,750 | 91 % |
| 8 | 0 | 0 | 0,750 | 84 % |
| 32 | 0 | 0 | 0,750 | 92 % |
| 64 | 0 | 0 | 0,750 | 94 % |

- Le potentiel n'augmente **jamais**, et les poids sont **toujours** décroissants vers le bas : les lemmes 1 et 2 tiennent à chaque pas.
- La part minimale du haut vaut **exactement 3/4** : la borne du lemme 3 est atteinte, elle est serrée.
- 84 à 94 % des phases font baisser $\Phi$ d'au moins 1/4, très au-dessus du 1/4 garanti : la preuve est pessimiste sur les constantes.

```text
 log₃ Φ   (fib(22), p = 8 : Φ₀ = 3^(2·CP − 1) = 3^85)
  85 ┤ ● ●
  80 ┤     ● ● ● ● ●
  70 ┤               ● ● ● ● ● ● ● ● ● ● ●
  60 ┤                                     ● ● ● ● ●
  50 ┤                                               ● ● ● ●
  40 ┤                                                       ● ● ● ● ●
  30 ┤                                                                 ●
  20 ┤ 
  10 ┤ 
   0 ┤                                                                   ●
     └─────────────────────────────────────────────────────────────────────→ phases (p = 8 tentatives de vol chacune)
       0         5         10        15        20        25        30
```

L'escalier descend de $2\,CP - 1 = 85$ à 0 en **33 phases**, là où la preuve en autorise au pire $\approx 325$ réussies. Elle surestime les constantes d'un facteur 10, mais prédit la bonne **forme** : un nombre de phases proportionnel à $CP$.

> [!note] Comparer avec la preuve de Graham
> Graham compte des **aires** : aire oisive $\le (m-1)\,CP$. Ici on compte des **jetons** : les instants « oisifs » deviennent des tentatives de vol, et on borne leur nombre en espérance. Même structure, mais l'aléa remplace l'oracle central.

### Vérifié par simulation

Simulation à pas unitaires du DAG de `fib(22)` : $W = 85\,969$ nœuds, $CP = 43$, parallélisme $W/CP \approx 2\,000$. Un nœud ou une tentative de vol dure un pas ; moyenne sur 5 tirages.

| $p$ | $T_p$ mesuré | $W/p + CP$ | tentatives de vol | tentatives $/(p \cdot CP)$ | vols réussis | migrations, file centrale |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 43 000 | 43 028 | 31 | 0,36 | 7 | 85 969 |
| 8 | 10 776 | 10 789 | 239 | 0,69 | 73 | 85 969 |
| 32 | 2 727 | 2 730 | 1 301 | 0,95 | 350 | 85 969 |
| 128 | 719 | 715 | 6 037 | 1,10 | 1 276 | 85 969 |
| 256 | 383 | 379 | 12 079 | 1,10 | 2 230 | 85 969 |

- $T_p$ colle à $W/p + CP$ (écart $\le 1\,\%$).
- Les tentatives de vol restent **de l'ordre de $p \cdot CP$** : le rapport plafonne vers 1,1.
- Quelques **centaines à milliers** de migrations, contre **toutes les 85 969 tâches** pour une file centrale.

**Le goulot de la file centrale.** Même simulation, mais la file ne peut servir que 8 accès par pas (un verrou a un débit fini) :

```text
 speedup      fib(22), W/CP ≈ 2 000          ◆ vol de travail   ■ file centrale (8 accès/pas)
 256 ┤
 128 ┤                                             ◆ 119,6
  64 ┤                                    ◆ 62
  32 ┤                           ◆ 31,5
  16 ┤                  ◆ 15,9
   8 ┤         ◆■ 8     ■ 8      ■ 8      ■ 8      ■ 8  ← plafond = débit de la file
   4 ┤◆■ 4
     └┬────────┬────────┬────────┬────────┬────────┬────────→ p
      4        8        16       32       64       128
```

Et quand le parallélisme manque — `fib(14)`, $W/CP = 68$ : à $p = 256$ le speedup n'est que de 49, et $T_p = 37$ s'approche de $CP = 27$. Le terme $O(CP)$ reprend la main dès que $p$ dépasse $W/CP$.

---

## 3. En pratique : le principe *work-first*

Cilk-5 (Frigo, Leiserson, Randall, 1998) tire la conséquence pratique du théorème. On écrit le temps réel avec deux surcoûts :

$$T_p \;\le\; c_1 \frac{T_S}{p} + c_\infty \, CP \qquad c_1 = \frac{W}{T_S}\ \text{(surcoût sur le travail)}, \quad c_\infty\ \text{(surcoût sur le chemin critique)}$$

où $T_S$ est le temps du programme **séquentiel** (sans aucune primitive parallèle).

> [!important] Principe *work-first*
> *Minimiser $c_1$, quitte à augmenter $c_\infty$.*
> Tant qu'il y a beaucoup plus de parallélisme que de cœurs (*parallel slackness* : $W/CP \gg p$), le terme $c_\infty\,CP$ est négligeable et $T_p \approx c_1\,T_S/p$. Tout ce qui ralentit **chaque** tâche se paie $W$ fois ; ce qui ne ralentit que les **vols** ne se paie que $O(p \cdot CP)$ fois.

Conséquences d'implémentation :

- **Créer une tâche doit coûter presque rien** : dans Cilk-5, un `spawn` coûte 2 à 6 appels de fonction C. Pour `fib`, qui ne fait rien d'autre que créer des tâches, $c_1 = 3{,}63$.
- **Tout le coût est repoussé sur le vol** : c'est le voleur qui fait le travail compliqué (synchronisation, recopie de contexte).
- **Pas de verrou pour le propriétaire** : protocole *THE* (Cilk-5), puis deque circulaire de **Chase–Lev** (2005). Le propriétaire empile et dépile en bas sans verrou ; le voleur prend en haut avec un `compare-and-swap` ; il n'y a conflit que lorsqu'il reste **un seul** élément.
- C'est aussi pourquoi le **seuil de récursion** reste indispensable ([[Tâches OpenMP — exemple Fibonacci#3. Seuil de récursion (*cutoff*)|fibo avec `n < 30`]]) : il fait baisser $c_1$ directement.

### Qui utilise le vol de travail

| Système | Détail |
| --- | --- |
| Cilk, Intel TBB, Java `ForkJoinPool`, Rust Rayon | deque par thread, vol aléatoire |
| Runtime OpenMP (tâches) | dépend de l'implémentation |
| **Go** (`runtime/proc.go`, vérifié sur go 1.22) | voir ci-dessous — c'est le TP du 20/11 |

> [!example] L'ordonnanceur de Go
> Lu dans `$(go env GOROOT)/src/runtime/proc.go` :
> - chaque **P** (processeur logique, `GOMAXPROCS` au total) a une **file locale** de 256 goroutines, plus un emplacement `runnext` pour la dernière créée ;
> - une **file globale** existe aussi, consultée en priorité **un tour sur 61** pour éviter la famine ;
> - un P sans travail tente jusqu'à **4 tours de vol**, en parcourant les autres P dans un **ordre aléatoire**, et **prend la moitié** de la file de la victime (`runqsteal`).
>
> Différences avec Cilk : la file locale est FIFO (et non LIFO), et on vole la moitié de la file plutôt qu'une seule tâche.

---

## 4. Repliement (*folding*) et schémas adaptatifs

> [!warning] Vocabulaire à confirmer avec le prof
> *Folding* n'apparaît dans aucun des articles consultés. Les deux lectures ci-dessous mènent à la même question, celle du **surcoût d'un algorithme parallèle à grain fin**.

### Replier un algorithme sur $p$ processeurs

Un algorithme parallèle « idéal » est écrit pour un nombre **illimité** de processeurs : $W_{par}$ opérations, profondeur $D$. On le **replie** sur $p$ processeurs réels en faisant exécuter par chacun plusieurs processeurs virtuels. Le **lemme de Brent** (1974) borne le résultat :

$$T_p \;\le\; \frac{W_{par}}{p} + D$$

C'est encore la forme de Graham. Mais **attention au $W_{par}$** : un algorithme parallèle à grain fin fait souvent **plus d'opérations** que le meilleur séquentiel.

> [!example] Le préfixe (*scan*) : $\pi_k = x_0 \circ x_1 \circ \dots \circ x_k$
> - Séquentiel : $n$ opérations.
> - Tout circuit parallèle de profondeur $d$ fait **au moins $2n - d$** opérations. Ladner–Fischer : $2n$ opérations, profondeur $2\log n$.
> - Replié sur $p$ processeurs : $T_p \approx 2n/p$. Avec $p = 2$, on ne gagne **rien** sur le séquentiel ($2n/2 = n$).
> - Borne inférieure (Nicolau–Wang) : $T_p \ge \lceil 2n/(p+1) \rceil$.

Replier un algorithme parallèle fait donc payer son surcoût **même quand le parallélisme ne sert pas** : sur 1 cœur, on exécute $2n$ opérations au lieu de $n$.

### L'idée adaptative : extraire le parallélisme **à la demande**

Les schémas adaptatifs (Roch, Traoré, Gautier… équipe MOAIS, Grenoble, runtime **Kaapi**) inversent la logique :

- **par défaut**, on exécute l'algorithme **séquentiel optimal** ;
- on ne crée du parallélisme **que lorsqu'un voleur se présente** : il **extrait** une part du travail restant (`extract_par`) ;
- en fin de morceau, on **fusionne** les résultats partiels (`merge`).

```text
   fold / réduction adaptative de [0, n) — le propriétaire avance de gauche à droite

   t₀   P0 ▶▶▶▶▶▶▶░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    (personne n'a volé : 0 surcoût)

   t₁   P0 ▶▶▶▶▶▶▶▶▶▶░░░░░░░░░░░░░░│P1 ░░░░░░░░░░░░░░░░░░░░    P1 oisif vole la MOITIÉ droite
                                     ▲ extract_par               de ce qui reste à P0

   t₂   P0 ▶▶▶▶▶▶▶▶▶▶▶▶▶▶▶░░░░░░░░│P1 ▶▶▶▶▶▶▶▶░░░│P2 ░░░░░░    P2 vole la moitié de P1

   t₃   P0 a fini sa part  ──▶  merge(r₀, r₁) ──▶ merge(·, r₂)   1 opération par fusion
```

- **Sans voleur**, l'exécution est **exactement** l'algorithme séquentiel optimal : surcoût nul.
- Chaque vol coûte **une** fusion. Comme le nombre de vols est $O(p \cdot CP)$, le surcoût reste petit.
- On ne fixe **jamais** $p$ ni la taille des blocs à l'avance : si un cœur est ralenti (machine partagée), les autres lui volent son travail.

> [!important] Résultat : préfixe adaptatif (Roch, Traoré, Bernard, Euro-Par 2006)
> Un processus séquentiel $P_s$ calcule les préfixes de gauche à droite ; les $p-1$ autres volent des intervalles à droite, y calculent des préfixes **locaux**, puis les **finalisent** quand $P_s$ les rattrape (un « saut » : une seule opération pour recoller). Avec $\Pi_{ave}$ la vitesse moyenne des processeurs :
> $$T_p \;\le\; \frac{2n}{(p+1)\,\Pi_{ave}} + O\!\left(\frac{\log n}{\Pi_{ave}}\right)$$
> C'est **asymptotiquement optimal** sur processeurs identiques (borne de Nicolau–Wang), et l'algorithme **ne connaît pas $p$**. Sur machine partagée, il bat l'algorithme optimal à $p$ fixé.

La même construction (Traoré, Roch, Maillard, Gautier, Bernard, Euro-Par 2008) donne des versions **optimales en travail** de `partial_sum`, `find_if`, `partition`, `unique_copy`, `remove_copy_if` et du tri STL. Elle remplace même la deque par une liste des vols réussis (vol de travail *deque-free*).

---

## 5. Les résultats à retenir

| Résultat | Énoncé | Ce qu'il dit |
| --- | --- | --- |
| Graham (1966) | glouton : $T \le W/m + CP$ | facteur 2 de l'optimal, mais liste **centrale** |
| Brent (1974) | repliement : $T_p \le W_{par}/p + D$ | un algorithme pour $\infty$ processeurs tourne sur $p$ |
| Blumofe–Leiserson (1999) | $\mathbb{E}[T_p] \le W/p + O(CP)$ ; $O(p \cdot CP)$ vols ; $S_p \le p\,S_1$ | même garantie, **distribuée**, communication bornée |
| Arora–Blumofe–Plaxton (1998) | potentiel $3^{2w}$ : chaque phase de $p$ vols détruit $\ge 1/4$ de $\Phi$ avec proba $\ge 1/4$ ; $O(W/p_A + CP\,p/p_A)$ | la **preuve** du $O(p \cdot CP)$, même avec un OS adversaire |
| Cilk-5 (1998) | $T_p \le c_1 T_S/p + c_\infty CP$ | *work-first* : rendre la création de tâche presque gratuite |
| Nicolau–Wang | préfixe : $T_p \ge \lceil 2n/(p+1)\rceil$ | le parallélisme a un coût en travail |
| Roch–Traoré–Bernard (2006) | préfixe adaptatif $\approx 2n/((p+1)\Pi_{ave})$ | on atteint la borne **sans connaître $p$** |

## Voir aussi

- [[Ordonnancement et théorème de Graham]] — la borne $W/m + CP$ et sa preuve par les aires
- [[Tâches OpenMP — exemple Fibonacci]] — le seuil de récursion, c'est-à-dire réduire $c_1$
- [[Parallélisme data flow — plus courts chemins]] — la seconde moitié du CM
- [[Go — goroutines et channels]] — pour le TP du 20/11 (vol de travail avec Go)
- [[Accélération et efficacité]] — l'accélération se mesure contre le **meilleur séquentiel** $T_S$, pas contre $W$

## Sources

- R. D. Blumofe, C. E. Leiserson, *[Scheduling Multithreaded Computations by Work Stealing](https://cs.utexas.edu/~venkatar/sys_perf_analysis/ws_theory.pdf)*, JACM 46(5), 1999 — Théorème 13, Lemme 12, Théorème 5 (mémoire)
- N. S. Arora, R. D. Blumofe, C. G. Plaxton, *[Thread Scheduling for Multiprogrammed Multiprocessors](https://people.cs.umass.edu/~emery/classes/cmpsci691s-fall2004/papers/arora98thread.pdf)*, SPAA 1998 (Theory Comput. Syst. 34, 2001) — potentiel, lemme structurel, *Top-Heavy Deques*, boules et urnes pondérées
- J. Shun, *[Work stealing analysis — MIT 6.506](https://jshun.csail.mit.edu/6506-s24/lectures/lecture9-1.pdf)* — résumé de la preuve
- M. Frigo, C. E. Leiserson, K. H. Randall, *[The Implementation of the Cilk-5 Multithreaded Language](https://people.cs.umass.edu/~emery/classes/cmpsci691w-spring2006/papers/cilk5.pdf)*, PLDI 1998 — principe *work-first*, protocole THE
- J.-L. Roch, D. Traoré, J. Bernard, *[On-line Adaptive Parallel Prefix Computation](https://www-id.imag.fr/~traored/WWW-documents/europar-prefixe-2006.pdf)*, Euro-Par 2006
- D. Traoré, J.-L. Roch, N. Maillard, T. Gautier, J. Bernard, *[Deque-free Work-optimal Parallel STL Algorithms](https://www-verimag.imag.fr/~rochj/perso_html/papers/2008-europar-adaptSTL.pdf)*, Euro-Par 2008
- D. Chase, Y. Lev, *Dynamic Circular Work-Stealing Deque*, SPAA 2005
- R. P. Brent, *The Parallel Evaluation of General Arithmetic Expressions*, JACM 21(2), 1974
- Go 1.22, `src/runtime/proc.go` — `findRunnable`, `stealWork`, `runqsteal`
- Simulations : `APP/demos/vol-de-travail/sim.py` (`python3 sim.py 22`) et `potentiel.py` (vérification des lemmes, ~30 s)
