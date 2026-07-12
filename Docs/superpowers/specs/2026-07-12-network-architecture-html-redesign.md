# Refonte du schéma d’architecture réseau

## Objectif

Transformer `schema-architecture-reseau.html` en un document autonome, moderne et immédiatement lisible, sans supprimer ni altérer les informations techniques existantes.

## Direction visuelle validée

Le document adopte une présentation claire de type « carte d’architecture » sur fond clair. Le bleu identifie l’infrastructure et les liaisons normales, l’orange l’héritage et les points de vigilance, et le vert l’architecture cible et les recommandations.

## Structure

1. En-tête synthétique avec contexte, objectif et indicateurs clés.
2. Navigation fixe vers les sections principales.
3. Comparaison immédiate de l’existant et de la cible.
4. Schéma de l’existant organisé verticalement par couches : opérateurs, FortiGate/VDOM, cœur, accès et services.
5. Chemin d’un paquet présenté séparément sous forme d’étapes numérotées.
6. Schéma cible reprenant la même organisation pour faciliter la comparaison.
7. Scénarios de migration, plan d’adressage et inventaire des interconnexions dans des tableaux lisibles, avec défilement horizontal uniquement sur petits écrans.
8. Notes techniques et détails secondaires regroupés dans des encarts ou sections repliables.

## Comportement et accessibilité

- Un seul fichier HTML, sans dépendance JavaScript.
- Mise en page responsive pour ordinateur, tablette et mobile.
- Typographie système avec secours local ; aucune dépendance nécessaire pour comprendre le document hors ligne.
- Contraste suffisant, légendes explicites et couleurs jamais utilisées comme seul vecteur d’information.
- Mode impression supprimant la navigation fixe, les ombres et les éléments décoratifs inutiles.
- Animations discrètes et désactivées avec `prefers-reduced-motion`.

## Conservation des données

Toutes les valeurs existantes sont conservées : équipements, ports, agrégats, VLAN, VDOM, routes, policies, adresses, scénarios, remarques, risques et sources. La refonte ne change que l’organisation visuelle et la formulation de titres ou légendes lorsque cela améliore la compréhension.

## Vérification

Le fichier final sera contrôlé pour vérifier : la validité structurelle du HTML, la présence des informations techniques de référence, l’absence de débordements majeurs en format bureau et mobile, et le rendu imprimable.
