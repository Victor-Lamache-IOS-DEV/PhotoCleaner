# 📸 PhotoCleaner — Nettoyeur de Photos iOS (Tinder Style)

Application native iOS SwiftUI pour trier et nettoyer la pellicule photo de votre iPhone.

## ✨ Fonctionnalités
- **Swipe Tinder** : Swipe droite (Garder 💚) / Swipe gauche (Jeter ❌).
- **Ordre aléatoire** : Les photos arrivent dans un ordre mélangé.
- **Mémoire persistante** : Les photos déjà classées ne sont plus jamais représentées.
- **Corbeille sécurisée** : Les suppressions sont groupées et validées en une seule fois par iOS, puis déplacées dans l'album *Supprimés récemment* (30 jours de sécurité).
- **Undo** : Annulation instantanée du dernier geste.
- **Design OLED Sombre** : Inspiré de Metro T18 avec retours haptiques natifs.

## 🚀 Build & Installation
Ce projet est totalement autonome. À chaque push sur GitHub, le workflow compile l'application, applique la signature Apple Developer et exporte `PhotoCleaner.ipa` dans les artefacts GitHub Actions.
