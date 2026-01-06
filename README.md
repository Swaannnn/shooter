# Godot 1v1 Shooter

Un FPS 1v1 nerveux développé avec Godot Engine 4.

## Fonctionnalités Implémentées

### 🔫 Arsenal
*   **Pistolet (1911)** : Arme de poing semi-automatique précise avec hitscan recoil.
*   **Fusil d'Assaut (M4A1)** : Arme automatique à cadence élevée.
*   **Fusil à Pompe (Mossberg)** : Tir dispersé (Multishot) dévastateur à courte portée.
*   **Système de Boutique** : Menu d'achat accessible en jeu (Touche `B`) pour changer d'arme dynamiquement.
*   **Effets Visuels** : Tracers de balles, impacts de particules, et recul procédural.

### 🏃 Mouvement Avancé
*   **Contrôleur FPS Fluide** : Gestion précise de la vélocité et de la gravité.
*   **État Crouching** (Accroupissement) : Réduction de la hitbox et de la caméra (Touche `Ctrl`).
*   **Slide Mechanics** : Glissade avec boost de vitesse et friction si activé pendant un sprint.
*   **Audio Immersif** : Sons de pas différenciés (Marche vs Course), Sauts et Tirs.

### ⚙️ Systèmes
*   **Menu de Pause** : Accessible via `Echap` avec gestion du curseur souris.
*   **Paramètres** :
    *   Sensibilité de la souris ajustable.
    *   Volume global ajustable.
*   **Architecture Modulaire** : Scripts séparés pour `Weapon`, `HitscanWeapon`, `PlayerController`.

## Commandes

*   **ZQSD / WASD** : Se déplacer
*   **Shift** : Courir
*   **Ctrl** : S'accroupir / Glisser (si en course)
*   **Espace** : Sauter
*   **Clic Gauche** : Tirer
*   **B** : Ouvrir la boutique d'armes
*   **Echap** : Menu Pause

## Installation

1.  Cloner le dépôt.
2.  Importer le projet dans Godot 4.x.
3.  Lancer `TestArena.tscn` pour tester.