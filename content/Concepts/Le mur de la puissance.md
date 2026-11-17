---
tags:
  - cours
  - parallelisme
  - architecture
up: "[[APP — MOC]]"
date: 2026-09-11
---

# Le mur de la puissance

> [!abstract] En une phrase
> Les fréquences ne montent plus, donc la performance ne vient plus « gratuitement » : il faut multiplier les cœurs, donc programmer en parallèle.

## Les fréquences ont cessé de croître

Elles stagnent entre **3 et 5 GHz depuis 20 ans**. La solution retenue par les constructeurs est d'augmenter le **nombre de cœurs** plutôt que la vitesse de chacun.

> C'est *la* raison d'être du [[Parallélisme C++#Créer des threads|multithreading]] : on ne gagne plus de performance à chaque génération de processeur sans rien changer au code.

## Vitesse de communication interne

La vitesse du courant dans une puce est d'environ **0,75 c**. Pendant un cycle d'horloge, le signal parcourt donc :

```
0,75 c / 3,5 GHz ≈ 6,4 cm
```

C'est la distance maximale qu'une information peut franchir en un cycle. Il faut donc des **mémoires petites et proches** pour être rapide — ce qui mène directement à la hiérarchie de caches et à la question de la [[Localité et caches|localité]].

## Voir aussi

- [[Localité et caches]] — la conséquence directe côté programmation
- [[Latence et débit — de l'horloge au réseau]] — la même idée du cache jusqu'à l'autre bout du monde, mesurée en cycles
- [[Machines de calcul — TOP500 et BOINC]] — ce que ça donne à l'échelle d'un supercalculateur
