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

## Cum functioneaza pe scurt

Aplicatia se bazeaza pe datele GTFS pentru a obtine informatii despre rutele de transport public. Aceste date sunt preluate in timp real si afisate pe harta, permitand utilizatorilor sa vada vehiculele in miscare. Modelul de predictie pentru estimari de timp e un k-nearest neighbors antrenat pe date istorice. Practic, cand vrem sa facem o predictie, luam pozitia actuala a vehiculului si ne uitam in trecut la momentele similare ca sa vedem cat a durat traseul atunci.

---
