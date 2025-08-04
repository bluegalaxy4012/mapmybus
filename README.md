# 🚌 MapMyBus

MapMyBus e o aplicatie simpla care arata in timp real detalii despre transportul public din orasul tau. Poti vedea vehiculele pe harta, cauta statii, salva vehicule favorite si verifica cand urmeaza sa soseasca.

Hostuit live pe:  
**https://mapmybus.marian.homes**

## Ce poti face in aplicatie

- Vezi pe harta toate vehiculele live (pe baza datelor GTFS realtime).
- Apesi pe o statie si afli urmatoarele sosiri care vor avea loc in acea statie.
- Alegi vehicule favorite si vezi doar ce te intereseaza. La fel, poti cauta doar statia pe care vrei sa o vezi.
- Primesti estimari a timpilor de sosire a unui vehicul in fiecare statie de pe ruta sa.

## Ce se foloseste

- **Frontend**: Flutter (build web, dar e pregatita si pentru mobile)
- **Backend**: FastAPI, cu modele de predictie incarcate din fisiere pkl
- **Hosting**: Nginx + Gunicorn pe un server personal
- **Date**: GTFS, de la API Tranzy

---
