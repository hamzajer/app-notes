---
tags:
  - cours
  - parallelisme
  - hpc
up: "[[APP — MOC]]"
date: 2026-09-11
updated: 2026-10-16
---

# Machines de calcul — TOP500 et BOINC

Deux façons opposées d'assembler de la puissance de calcul : une machine unique très couplée, ou une multitude de machines sans aucun lien.

## High Performance Linpack

Le **HPL** est le benchmark qui classe les machines du TOP500 : résolution d'un grand système linéaire dense, en **F64** (double précision).

**El Capitan** (n° 1) :

| Caractéristique | Valeur |
| --- | --- |
| Performance HPL | **1,742 Exaflop/s** |
| Performance HPCG | 17,41 Pflop/s |
| Cœurs | ~11 millions — AMD EPYC 24C + AMD Instinct MI300A |
| Réseau | Slingshot-11 |
| Stockage | 2/3 de la machine |
| Consommation | 29 MW, soit ~3 % d'une tranche nucléaire |

> [!tip] HPL vs HPCG
> Deux ordres de grandeur d'écart entre les deux chiffres. HPL est un calcul dense et régulier, taillé pour les unités de calcul ; HPCG est creux et irrégulier, donc limité par les accès mémoire. Les applications réelles ressemblent bien plus à HPCG — voir [[Localité et caches]].

El Capitan est n° 1 de juin 2025 à juin 2026. Le TOP500 est 100 % sous Linux depuis une décennie ; 26 machines françaises, 156 dans l'UE élargie.

## Et sans accélérateur : Fugaku

**Fugaku** (Fujitsu, RIKEN), 7ᵉ du TOP500 :

| Caractéristique | Valeur |
| --- | --- |
| Cœurs | 7,6 M de cœurs ARM 64 bits (48 par processeur), 158 976 nœuds, **sans accélérateur séparé** |
| Réseau | Tofu, 100 Gib/s, 90 ns de latence matérielle, *fat tree* |
| Performance | 442 Pflop/s |
| Consommation | 29,9 MW |

Exploiter des accélérateurs est plus complexe (bibliothèques, mémoire séparée) : **53 % du TOP500 s'en passe**.

## Accélérateur graphique

*(non traité par le cours — voir l'UE 5MMGPUHP de 3A)*

## BOINC — le supercalculateur planétaire

Issu de **SETI@home**, géré par Berkeley : des volontaires offrent la puissance de calcul de leur machine personnelle.

Au 15 janvier 2024 : **3,04 Pflop/s** sur 24 h, ce qui le placerait au rang ~275 du TOP500.

BOINC n'exécute que des applications *embarrassingly parallel* : beaucoup de calcul indépendant, très peu d'échanges d'informations.

> [!note] Pourquoi cette contrainte
> Aucune [[Parallélisme C++#Data race|donnée partagée]] entre les tâches : pas de `mutex`, pas de `condition_variable`, donc aucune synchronisation à payer. C'est la seule façon de tolérer un « réseau » fait d'internet et de machines qui s'éteignent sans prévenir.

## Voir aussi

- [[Le mur de la puissance]] — pourquoi ces machines ont des millions de cœurs
- [[Accélération et efficacité]] — comment on mesure ce que rapporte un cœur de plus
