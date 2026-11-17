---
tags:
  - cours
  - parallelisme
  - reseau
  - systeme
  - performance
up: "[[APP — MOC]]"
date: 2026-10-13
status: à-réviser
---

# Latence et débit — de l'horloge au réseau

> [!abstract] En une phrase
> On mesure tout **en cycles d'horloge** du processeur : un cache coûte quelques cycles, la RAM quelques centaines, l'OS des milliers, le réseau des millions à des centaines de millions. Chaque niveau qui s'éloigne du cœur coûte **un ou plusieurs ordres de grandeur** de plus.

## Trois mots à ne pas confondre

| Terme | Question | Unité | Analogie (autoroute) |
| --- | --- | --- | --- |
| **Latence** | combien de temps pour que le **premier** octet arrive ? | s (ns, µs, ms) | durée du trajet d'une voiture |
| **Bande passante** | quel débit **maximal** le lien permet-il ? | octets/s, bits/s | nombre de voies × vitesse limite |
| **Débit** (*throughput*) | quel débit obtient-on **réellement** ? | octets/s | voitures qui arrivent vraiment par heure |

Le débit est toujours **inférieur** à la bande passante : protocoles, en-têtes, retransmissions, contention. La part **utile** pour l'application s'appelle le *goodput*.

> [!warning] Latence et bande passante sont indépendantes
> Un camion de disques durs entre Paris et Lyon : bande passante énorme (des pétaoctets), latence de 5 heures. Un ping sur un réseau local : latence minuscule, très peu de données. Améliorer l'une n'améliore pas l'autre.

### Le modèle qui relie les deux

Le temps pour transférer $n$ octets (vu dans [[Mémoire partagée vs mémoire distribuée#Le coût d'un message|le coût d'un message]]) :

$$T(n) = \underbrace{\alpha}_{\text{latence}} + \underbrace{\frac{n}{\beta}}_{\text{transfert}} \qquad\qquad \text{débit effectif} = \frac{n}{T(n)}$$

- **Petits messages** : $T \approx \alpha$, c'est la latence qui domine.
- **Gros messages** : $T \approx n/\beta$, c'est la bande passante qui domine.
- Le basculement se fait vers $n_{1/2} = \alpha \beta$ : la taille à partir de laquelle on obtient **la moitié** de la bande passante.

### Le produit latence × bande passante

$$\text{BDP} = \beta \times \text{RTT}$$

C'est la quantité de données **« en vol »** sur le lien : envoyées mais pas encore acquittées. Pour remplir le tuyau, il faut avoir au moins autant de données en cours d'envoi.

> [!example] Exemple
> Lien de 1 Gbit/s vers New York, RTT ≈ 90 ms : $10^9 \times 0{,}09 = 9 \times 10^7$ bits ≈ **11 Mo** en vol. Un protocole qui attend l'accusé de réception après chaque paquet de 64 Ko n'utiliserait qu'une infime partie du lien.

---

## L'horloge comme unité de mesure

Toutes les valeurs ci-dessous ont été **mesurées sur ce portable** : Intel Core i5-8265U, 4 cœurs, sur batterie (gouverneur `powersave`), fréquence mesurée **1,84 GHz**, donc **1 cycle ≈ 0,54 ns**.

> [!info] Comment c'est mesuré
> - **Fréquence** : chaîne d'additions dépendantes (1 addition = 1 cycle).
> - **Caches et RAM** : *pointer chasing*, chaque lecture donne l'adresse de la suivante, sur un tableau mélangé de 16 Ko (L1), 128 Ko (L2), 2 Mo (L3) ou 512 Mo (RAM). Le processeur ne peut ni anticiper ni paralléliser.
> - **OS** : appel système `getppid`, ping-pong d'un octet entre deux processus par `pipe` sur le même cœur (changement de contexte), `fdatasync` après une écriture de 4 Ko.
> - **Réseau** : ping-pong MPI (voir [[MPI]]) et `ping` vers des serveurs de datacenters connus.
> Valeurs moyennées sur 3 passes. Les cycles L1 (4) et L2 (12) correspondent à la documentation Intel de cette génération, ce qui valide la calibration.

| Opération                                  | Temps   |       Cycles | Si 1 cycle durait 1 s |
| ------------------------------------------ | ------- | -----------: | --------------------- |
| 1 cycle d'horloge                          | 0,54 ns |            1 | 1 s                   |
| lecture cache **L1**                       | 2,2 ns  |            4 | 4 s                   |
| lecture cache **L2**                       | 6,5 ns  |           12 | 12 s                  |
| `mutex` lock + unlock (sans contention)    | 13 ns   |           24 | 24 s                  |
| lecture cache **L3**                       | 29 ns   |           53 | 53 s                  |
| lecture **RAM**                            | 197 ns  |          362 | **6 min**             |
| appel système                              | 211 ns  |          388 | 6,5 min               |
| message MPI, mémoire partagée              | 0,5 µs  |        ≈ 900 | 15 min                |
| changement de contexte                     | 3,5 µs  |        6 440 | **1 h 50**            |
| message MPI via la pile TCP (même machine) | 19 µs   |       35 000 | 10 h                  |
| écriture SSD 4 Ko + `fsync`                | 450 µs  |      828 000 | **9,6 jours**         |
| ping box / passerelle                      | 2,2 ms  |   4 millions | 1,5 mois              |
| ping Francfort                             | 28 ms   |  52 millions | 1,7 an                |
| ping Newark (New Jersey)                   | 91 ms   | 167 millions | **5,3 ans**           |
| ping Tokyo                                 | 243 ms  | 447 millions | 14 ans                |
| ping Sydney                                | 306 ms  | 563 millions | **18 ans**            |

```text
 cycles (échelle log)   10⁰   10¹   10²   10³   10⁴   10⁵   10⁶   10⁷   10⁸   10⁹
                        │     │     │     │     │     │     │     │     │     │
 ── PROCESSEUR ─────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
 cache L1               ████                                                    4
 cache L2               ██████                                                  12
 mutex                  ████████                                                24
 cache L3               ██████████                                              53
 ── MÉMOIRE ────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
 RAM                    ███████████████                                         362
 ── SYSTÈME (OS) ───────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
 appel système          ████████████████                                        388
 changement de contexte ███████████████████████                                 6 440
 SSD + fsync            ████████████████████████████████████                    828 000
 ── RÉSEAU ─────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
 MPI mémoire partagée   ██████████████████                                      ≈ 900
 MPI via TCP            ███████████████████████████                             35 000
 passerelle             ████████████████████████████████████████                4·10⁶
 Francfort              ██████████████████████████████████████████████          5·10⁷
 New Jersey             █████████████████████████████████████████████████       2·10⁸
 Sydney                 █████████████████████████████████████████████████████   6·10⁸
```

> [!tip] La lecture à retenir
> Entre un accès L1 et un ping vers Sydney : **8 ordres de grandeur**. Si le cœur attendait 4 secondes pour son cache L1, il attendrait **18 ans** la réponse de Sydney. C'est pourquoi un calcul parallèle distribué doit **éviter de communiquer**, et sinon **grouper** ses messages et **recouvrir** l'attente par du calcul.

### Comparaison avec la liste de référence

Les ordres de grandeur concordent avec la liste « *Latency Numbers Every Programmer Should Know* » (Jeff Dean, ~2012) :

| Opération | Jeff Dean (~2012) | Mesuré ici |
| --- | --- | --- |
| L1 | 0,5 ns | 2,2 ns |
| L2 | 7 ns | 6,5 ns |
| `mutex` lock/unlock | 25 ns | 13 ns |
| RAM | 100 ns | 197 ns |
| aller-retour dans un datacenter | 500 µs | — |
| Californie → Pays-Bas → Californie | 150 ms | Grenoble ↔ Californie : 153 ms |

L'écart sur L1 et RAM vient surtout de la fréquence : à 1,84 GHz au lieu de ~3,5 GHz, chaque cycle dure deux fois plus longtemps. **En cycles**, les valeurs sont stables d'une machine à l'autre ; **en nanosecondes**, elles dépendent de la fréquence. D'où l'intérêt de raisonner en cycles.

---

## Le système d'exploitation coûte cher

Trois mesures isolent le coût de l'OS :

| | Cycles | Ce qui se passe |
| --- | ---: | --- |
| appel système | ~390 | passage mode utilisateur → noyau → retour |
| changement de contexte | ~6 400 | le noyau sauvegarde un processus, en restaure un autre (registres, pile, caches et TLB à recharger) |
| message MPI : mémoire partagée vs pile TCP | 900 vs 35 000 | **même machine, même message** : seul change le fait de passer ou non par la pile réseau du noyau |

> [!note] Facteur 40 dû au noyau
> En mémoire partagée, Open MPI copie directement dans une zone commune aux deux processus, sans appel système. Par TCP, chaque message traverse la pile réseau du noyau, même en local. C'est pour cela que les réseaux HPC (InfiniBand, [[Machines de calcul — TOP500 et BOINC|Slingshot]]) font du **RDMA** : la carte réseau écrit directement dans la mémoire du processus distant, **sans passer par l'OS**.

---

## Le débit : l'autre axe

### Ping-pong MPI mesuré

Message de $n$ octets aller-retour entre 2 processus, temps d'un **aller simple** :

| Taille | Mém. partagée : temps | débit | Pile TCP : temps | débit |
| ---: | ---: | ---: | ---: | ---: |
| 64 o | 0,4 µs | 0,2 Go/s | 21 µs | 0,003 Go/s |
| 1 Ko | 0,8 µs | 1,2 Go/s | 16 µs | 0,06 Go/s |
| **4 Ko** | **3,9 µs** ⚠️ | 1,1 Go/s | 19 µs | 0,2 Go/s |
| 64 Ko | 15 µs | 4,3 Go/s | 98 µs | 0,7 Go/s |
| 1 Mo | 177 µs | **5,9 Go/s** | 458 µs | 2,3 Go/s |
| 64 Mo | 18 ms | 3,7 Go/s | 28 ms | **2,4 Go/s** |

```text
 débit effectif (Go/s)
 6 ┤                                           ●   ← β ≈ 6 Go/s, mémoire partagée (●)
 5 ┤                                     ●
 4 ┤                               ●                 ●     ●
 3 ┤
 2 ┤                         ●                 ○     ○     ○   ← β ≈ 2,3 Go/s, pile TCP (○)
 1 ┤       ●     ●     ●     ○     ○     ○
 0 ┼ ◐     ○     ○     ○
    64o   256o  1Ko   4Ko   16Ko  64Ko  256Ko 1Mo   4Mo   16Mo
    └──── la latence α domine ────┘  └── la bande passante β domine ──┘
```

● mémoire partagée, ○ pile TCP, ◐ les deux confondus. Ce qu'on lit :

- **À gauche**, le débit est ridicule : chaque message paie la latence $\alpha$ (0,5 µs en mémoire partagée, ~20 µs par TCP) pour presque rien transférer.
- **À droite**, le débit plafonne à $\beta$.
- La moitié de $\beta$ est atteinte vers 16 Ko en mémoire partagée et vers 200 Ko par TCP : plus $\alpha$ est grand, plus il faut de gros messages pour l'amortir ($n_{1/2} = \alpha\beta$).
- **Le saut à 4 Ko** (0,8 → 3,9 µs) : Open MPI passe du protocole *eager* au protocole *rendez-vous*. C'est le même seuil qui faisait bloquer l'échange symétrique dans [[MPI#Le piège : l'interblocage|le piège de l'interblocage]].
- Au-delà de quelques Mo, le débit en mémoire partagée **redescend** : le message ne tient plus dans le cache L3 (6 Mo), la copie se fait à la vitesse de la RAM.

### Débit mémoire et calcul

Débit séquentiel mesuré de la RAM, sur un seul cœur : **10 Go/s**, soit environ $10 / 1{,}84 \approx 5{,}5$ octets par cycle — **moins d'un `double` par cycle**.

> [!warning] Conséquence : beaucoup de calculs sont limités par la mémoire
> Un produit scalaire lit 2 `double` (16 octets) pour une multiplication-addition. À 5,5 octets/cycle, la mémoire fournit une opération tous les ~3 cycles, alors que le cœur peut en faire plusieurs par cycle. Le calcul attend la RAM : c'est l'écart entre les chiffres HPL et HPCG d'[[Machines de calcul — TOP500 et BOINC#High Performance Linpack|El Capitan]], et la raison d'être de la [[Localité et caches|localité]].

---

## La distance : la lumière comme borne

Rien ne va plus vite que la lumière. Dans une fibre optique, elle avance à environ **2/3 de c**, soit ~200 000 km/s. On en déduit un RTT minimal incompressible :

$$\text{RTT}_{\min} = \frac{2 \times \text{distance}}{200\,000 \text{ km/s}}$$

| Depuis Grenoble | Distance (orthodromie) | Borne physique | Mesuré | Mesuré / borne |
| --- | ---: | ---: | ---: | ---: |
| Francfort | 590 km | 5,9 ms | 28,5 ms | ×4,8 |
| Newark (New Jersey) | 6 250 km | 63 ms | 91 ms | ×1,5 |
| Fremont (Californie) | 9 430 km | 94 ms | 153 ms | ×1,6 |
| Tokyo | 9 900 km | 99 ms | 243 ms | ×2,5 |
| Sydney | 16 830 km | 168 ms | 306 ms | ×1,8 |

- Sur les longues distances, on est à **1,5–2,5 fois** la limite physique : les câbles ne suivent pas l'orthodromie, et chaque routeur ajoute du temps.
- Sur les courtes distances, ce sont les **équipements** (Wi-Fi, box, routeurs) qui dominent, pas la distance : Francfort est à ×4,8.

> [!danger] Une mesure peut être physiquement impossible
> `ping www.sydney.edu.au` a répondu en **8,7 ms**. La borne pour Sydney est 168 ms : le serveur qui répond n'est donc **pas** à Sydney mais dans un relais en Europe (CDN). Toujours confronter une mesure à la borne physique.

> [!tip] Même idée à l'échelle d'une puce
> À 3,5 GHz, un signal parcourt ~6,4 cm par cycle ([[Le mur de la puissance#Vitesse de communication interne|vitesse de communication interne]]) : la distance limite déjà la taille d'un processeur. À l'échelle de la planète, un aller-retour vers Sydney dure 560 millions de cycles.

---

## Et l'heure, dans un système distribué ?

Chaque machine a **sa propre horloge**, et elles dérivent les unes par rapport aux autres. Il n'existe pas d'heure commune exacte.

- MPI le dit explicitement : l'attribut `MPI_WTIME_IS_GLOBAL` vaut **0** sur cette installation, donc les `MPI_Wtime()` de deux processus **ne sont pas comparables**. Seules les **durées** mesurées sur un même processus ont un sens (même règle que [[Parallélisme C++#Mesurer le temps|`CLOCK_MONOTONIC`]]).
- C'est pourquoi le ping-pong mesure un **aller-retour** sur le processus 0 et divise par deux, au lieu de comparer l'heure d'envoi de l'un à l'heure de réception de l'autre.
- Quand il faut seulement **ordonner** les événements, Lamport (1978) remplace l'heure par une **horloge logique** : un compteur incrémenté à chaque événement et transmis dans les messages, qui respecte la causalité (« a s'est produit avant b ») sans aucune synchronisation physique.

---

## Les leçons

1. **Raisonner en cycles** : les nanosecondes changent avec la fréquence, les cycles restent stables.
2. **Ne pas communiquer** si on peut l'éviter : chaque niveau franchi coûte un ou plusieurs ordres de grandeur.
3. **Grouper** les petits messages : on paie la latence $\alpha$ une seule fois.
4. **Recouvrir** la latence par du calcul (`MPI_Isend`/`MPI_Irecv`, voir [[MPI#Communications non bloquantes|non bloquant]]).
5. **Éviter le noyau** sur le chemin critique : appels système et changements de contexte coûtent des milliers de cycles.

## Voir aussi

- [[Le mur de la puissance]] — la vitesse de propagation à l'échelle d'une puce
- [[Localité et caches]] — exploiter les niveaux rapides de la hiérarchie
- [[Mémoire partagée vs mémoire distribuée]] — le modèle $\alpha + n/\beta$ et la décomposition de domaine
- [[MPI]] — eager vs rendez-vous, non bloquant

## Sources

- Jeff Dean, Peter Norvig, *[Latency Comparison Numbers (~2012)](https://gist.github.com/jboner/2841832)* — la liste de référence
- Wikipedia, *[Bandwidth-delay product](https://en.wikipedia.org/wiki/Bandwidth-delay_product)* — définition, données en vol
- Wikipedia, *[Network throughput](https://en.wikipedia.org/wiki/Network_throughput)* — bande passante vs débit vs *goodput*
- GeeksforGeeks, *[Difference between Latency and Throughput](https://www.geeksforgeeks.org/computer-networks/difference-between-latency-and-throughput/)*
- L. Lamport, *[Time, Clocks, and the Ordering of Events in a Distributed System](https://lamport.azurewebsites.net/pubs/time-clocks.pdf)*, CACM, 1978 — horloges logiques
- Mesures : programmes C (`gcc -O2`) et Open MPI 4.1.6 sur i5-8265U, 13/10/2026 ; `ping` vers les serveurs `speedtest.*.linode.com`
