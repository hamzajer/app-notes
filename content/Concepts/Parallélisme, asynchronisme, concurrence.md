---
tags:
  - cours
  - parallelisme
  - vocabulaire
up: "[[APP — MOC]]"
date: 2026-09-11
updated: 2026-10-16
---

# Parallélisme, asynchronisme, concurrence

Trois notions **indépendantes** que l'on confond systématiquement. Elles sont reprises côté code dans [[Parallélisme C++#Vocabulaire|le vocabulaire C++]].

| Notion | Définition | En C++ |
| --- | --- | --- |
| **Parallélisme** | Faire plusieurs choses **simultanément**. Ce n'est pas du temps partagé : il faut du matériel en plusieurs exemplaires, et chaque exécution a son propre flot d'instructions. | [[Parallélisme C++#Créer des threads\|`std::thread`]] — un flot d'instructions par thread |
| **Asynchronisme** | L'événement attendu arrivera dans le futur, mais **sa date d'occurrence n'est pas maîtrisée**. | [[Parallélisme C++#Mutex et `condition_variable`\|`condition_variable`]] — on s'endort en attendant plutôt que de faire de l'attente active |
| **Concurrence** | Utilisation par plusieurs flots d'une **même entité**, principalement la mémoire pour des données partagées. | [[Parallélisme C++#Data race\|data race]] sur `a++`, résolue par `mutex`, échange de messages ou `atomic` |

> [!example] Les trois sont bien indépendantes
> - Concurrence **sans** parallélisme : deux threads en temps partagé sur un seul cœur — ils se marchent dessus sans jamais s'exécuter en même temps.
> - Parallélisme **sans** concurrence : une application *[[Machines de calcul — TOP500 et BOINC#BOINC — le supercalculateur planétaire|embarrassingly parallel]]*, aucune donnée partagée.
> - Asynchronisme **sans** parallélisme : une entrée/sortie sur un seul cœur.

> [!tip] La phrase à retenir (CM2)
> **Les difficultés viennent de la concurrence. Les gains de temps viennent du parallélisme.**

## Voir aussi

- [[Parallélisme C++]] — la traduction en code de ces trois notions
- [[Ordonnancement et théorème de Graham]] — ce que devient le parallélisme quand il faut le distribuer sur $m$ cœurs
- [[Go — goroutines et channels]] — en Go, la concurrence passe par les channels
