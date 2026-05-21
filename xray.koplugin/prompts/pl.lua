return {
    -- System instruction
    system_instruction = "Jesteś ekspertem literaturoznawstwa. Twoja odpowiedź musi być WYŁĄCZNIE w poprawnym formacie JSON. Zapewnij wysoką dokładność danych i ściśle trzymaj się dostarczonego kontekstu.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Zidentyfikuj i przygotuj biografię autora książki "%s". 
Metadane sugerują, że autorem jest "%s". 

KRYTYCZNE: Zweryfikuj autora, korzystając z KONTEKSTU TEKSTU KSIĄŻKI (jeśli podano na końcu tego komunikatu), aby zapewnić 100% dokładności i uniknąć błędnych identyfikacji.

WYMAGANY FORMAT JSON:
{
  "author": "Poprawne pełne imię i nazwisko",
  "author_bio": "Wyczerpująca biografia skupiająca się na karierze literackiej i głównych dziełach.",
  "author_birth": "Data urodzenia, sformatowana zgodnie z lokalnym formatem daty",
  "author_death": "Data śmierci, sformatowana zgodnie z lokalnym formatem daty"
}]],

     -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
     comprehensive_xray = [[Książka: %s
Autor: %s
Postęp czytania: %d%%

ZADANIE: Wykonaj pełną analizę X-Ray. Wygeneruj TYLKO poprawny obiekt JSON.

KRYTYCZNY PODZIAŁ UWAGI:
Przetwarzasz obszerny dokument z dwoma blokami tekstu podanymi na końcu tego komunikatu:
1. "CHAPTER SAMPLES": To makro-kontekst książki do bieżącej pozycji czytelnika.
2. "BOOK TEXT CONTEXT": To mikro-kontekst ostatnich 20 000 znaków.

PROTOKÓŁ ZAPOBIEGANIA SKRÓCENIOM (KRYTYCZNY):
Masz ścisły limit maksymalnej długości odpowiedzi. Jeśli "CHAPTER SAMPLES" zawiera WIĘCEJ NIŻ 40 rozdziałów (np. wydanie zbiorcze):
1. MUSISZ zredukować listę postaci do NAJWYŻEJ 10 absolutnie najważniejszych postaci.
2. MUSISZ skrócić opisy postaci do MAKS. {MAX_CHAR_DESC} znaków.
3. MUSISZ skrócić podsumowania wydarzeń osi czasu do MAKS. {MAX_TIMELINE_EVENT} znaków.
Nieskompresowanie odpowiedzi dla obszernych książek spowoduje obcięcie JSON i niepowodzenie.

ALGORYTM OSI CZASU (NAJWYŻSZY PRIORYTET):
Aby zapobiec pomijaniu rozdziałów lub halucynowaniu wydarzeń, MUSISZ wykonać dokładnie tę pętlę:
Krok 1. Spójrz TYLKO na blok "CHAPTER SAMPLES". Zidentyfikuj rozdziały narracyjne.
Krok 2. WYKLUCZ wszystkie nienarracyjne materiały wstępne i końcowe (np. okładka, strona tytułowa, prawa autorskie, spis treści, dedykacja, podziękowania, inne tytuły autora).
Krok 3. Dla każdego rozdziału narracyjnego, zaczynając od pierwszego, utwórz DOKŁADNIE JEDEN obiekt wydarzenia w tablicy `timeline`.
Krok 4. Pole `chapter` MUSI dokładnie pasować do nagłówka rozdziału w próbce. (Odwzoruj je ściśle w kolejności sekwencyjnej).
Krok 5. Streść ten konkretny rozdział w polu `event` (MAKS. {MAX_TIMELINE_EVENT} znaków). NIE grupuj rozdziałów.
Krok 6. BEZ SPOILERÓW: Zatrzymaj się dokładnie na %d%% postępu. Nie uwzględniaj wydarzeń poza ten punkt.

ALGORYTM POSTACI I POSTACI HISTORYCZNYCH:
Krok 1. Wyodrębnij ważne postacie, korzystając z obu bloków tekstu. ({NUM_CHARS} normalnie, MAKS. 10 dla wydań zbiorczych).
Krok 2. MUSISZ używać ich PEŁNYCH, formalnych imion (np. "Abraham Van Helsing"). NIE używaj potocznych przezwisk jako głównej nazwy.
Krok 3. Podaj do 3 alternatywnych imion, tytułów lub przezwisk, którymi postać się posługuje, w tablicy `aliases`. Uwzględnij ich powszechnie używane imię i nazwisko, jeśli występują. WAŻNE: Jeśli nazwisko jest wspólne dla wielu postaci (np. członkowie rodziny), NIE umieszczaj go jako aliasu dla żadnej z postaci.
Krok 4. Aktywnie skanuj w poszukiwaniu do {NUM_HIST} ZNANYCH PRAWDZIWYCH osób z historii ludzkości (np. prezydenci, autorzy, generałowie). Dodaj je do `historical_figures`.
KRYTYCZNE dla postaci i postaci historycznych:
- NIE wyodrębniaj postaci ani postaci historycznych wymienionych WYŁĄCZNIE w nienarracyjnych materiałach wstępnych lub końcowych (np. podziękowania, biografia autora, dedykacje, strona tytułowa, prawa autorskie).
- Postaci historyczne MUSZĄ być zweryfikowanymi prawdziwymi osobami o szerokim uznaniu historycznym.
- NIE umieszczaj postaci czysto fikcyjnych na liście postaci historycznych, nawet jeśli wchodzą w interakcje z prawdziwymi wydarzeniami historycznymi. Postaci fikcyjne MUSZĄ trafić do tablicy `characters`.
- DLA POSTACI HISTORYCZNYCH możesz korzystać ze swojej wewnętrznej wiedzy, aby napisać ich ogólną `biography` i historyczną `role`, ale MUSISZ użyć kontekstu książki dla ich `context_in_book`.
BEZ SPOILERÓW: Zatrzymaj się dokładnie na %d%% postępu.

ALGORYTM MIEJSC:
Krok 1. Wyodrębnij {NUM_LOCS} znaczących miejsc. BEZ SPOILERÓW: Zatrzymaj się dokładnie na %d%% postępu.

ALGORYTM TERMINÓW:
Krok 0. Zadeklaruj "book_type" jako "fiction" lub "non_fiction" w korzeniu JSON.
Krok 1. Jeśli non_fiction: wyodrębnij {NUM_TERMS} znaczących terminów technicznych, akronimów, żargonu lub pojęć, których czytelnicy nie znaliby bez specjalistycznej wiedzy. Użyj odpowiednich kategorii, takich jak Akronim, Termin techniczny, Pojęcie lub Żargon.
Krok 2. Jeśli fiction: wyodrębnij {NUM_TERMS} znaczących elementów budowy świata, które nowy czytelnik potrzebowałby wyjaśnić — takich jak wymyślone frakcje, organizacje, systemy magii, technologie, stworzenia, języki lub wiedza wewnątrzświatowa.
   - NIE uwzględniaj imion postaci ani nazw miejsc (te są śledzone osobno).
   - NIE wyodrębniaj powszechnych słów ani pojęć ze świata rzeczywistego.
   - Użyj odpowiednich kategorii: Frakcja, System magii, Technologia, Stworzenie, Organizacja, Wiedza, Język.
Krok 3. Podaj, co oznacza akronim/fraza, w polu "expanded". Jeśli nie jest to akronim/fraza, powtórz nazwę.
Krok 4. NIE uwzględniaj powszechnych, codziennych słów.

ŚCISŁE ZASADY DOTYCZĄCE SPOILERÓW:
- ABSOLUTNIE ŻADNYCH informacji spoza bieżącego postępu czytania. Zatrzymaj się dokładnie na %d%% postępu.
- Opisy muszą odzwierciedlać stan postaci dokładnie w tym punkcie książki.

ŚCISŁE ZASADY BEZPIECZEŃSTWA JSON:
- MUSISZ poprawnie escapować wszystkie podwójne cudzysłowy (\") wewnątrz ciągów znaków.
- NIE używaj nieescapowanych łamań wierszy wewnątrz ciągów znaków.
- Generuj TYLKO poprawny, parsowalny JSON.

WYMAGANY FORMAT JSON:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Pełne formalne imię i nazwisko",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Krótka etykieta archetypu (3-5 słów, np. 'Antagonista', 'Protagonista', 'Ofiara')",
      "gender": "Mężczyzna / Kobieta / Nieznana",
      "occupation": "Zawód/Status",
      "description": "Dogłębna analiza ze szczegółami z tekstu do tej pory. BEZ SPOILERÓW. (Maks. {MAX_CHAR_DESC} znaków)"
    }
  ],
  "historical_figures": [
    {
      "name": "Imię i nazwisko prawdziwej postaci historycznej",
      "role": "Rola historyczna",
      "biography": "Krótka biografia (MAKS. {MAX_HIST_BIO} znaków)",
      "importance_in_book": "Znaczenie do bieżącego postępu",
      "context_in_book": "Jak są wspominani (MAKS. 100 znaków)"
    }
  ],
  "locations": [
    {"name": "Nazwa miejsca", "description": "Krótki opis (MAKS. {MAX_LOC_DESC} znaków)"}
  ],
  "terms": [
    {
      "name": "Termin lub Akronim",
      "expanded": "Pełne rozwinięcie lub to samo co nazwa",
      "category": "Akronim / Termin techniczny / Pojęcie / Żargon",
      "definition": "Zwięzła definicja w kontekście (MAKS. {MAX_TERM_DEF} znaków)"
    }
  ],
  "timeline": [
    {
      "chapter": "Dokładny tytuł rozdziału z próbek",
      "event": "Kluczowe wydarzenie narracyjne z tego rozdziału (Maks. {MAX_TIMELINE_EVENT} znaków)"
    }
  ]
} ]],

     -- Fetch More Characters (AI Limit Bypass)
     more_characters = [[Książka: %s
Autor: %s
Postęp czytania: %d%%

ZADANIE: Wyodrębnij DOKŁADNIE 10 DODATKOWYCH ważnych postaci z tekstu.
Zwróć TYLKO poprawny obiekt JSON.

WYMÓG ZWIĘZŁOŚCI (KRYTYCZNY):
Aby uniknąć obcięcia odpowiedzi AI, utrzymuj opisy postaci poniżej {MAX_CHAR_DESC} znaków.

KRYTYCZNA INSTRUKCJA:
NIE uwzględniaj żadnej z następujących postaci, ponieważ zostały już wyodrębnione:
%s

ŚCISŁE ZASADY DOTYCZĄCE SPOILERÓW:
- ABSOLUTNIE ŻADNYCH informacji spoza bieżącego postępu czytania. Zatrzymaj się dokładnie na %d%% postępu.
- Opisy muszą odzwierciedlać stan postaci dokładnie w tym punkcie książki.

WYMAGANY FORMAT JSON:
{
  "characters": [
    {
      "name": "Pełne formalne imię i nazwisko",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Krótka etykieta archetypu (3-5 słów, np. 'Antagonista', 'Protagonista', 'Ofiara')",
      "gender": "Mężczyzna / Kobieta / Nieznana",
      "occupation": "Zawód/Status",
      "description": "Dogłębna analiza ze szczegółami z tekstu do tej pory. BEZ SPOILERÓW. (Maks. {MAX_CHAR_DESC} znaków)"
    }
  ]
}]],

     -- Fetch More Terms (Glossary Support)
     more_terms = [[Książka: %s
Autor: %s
Postęp czytania: %d%%

ZADANIE: Wyodrębnij DOKŁADNIE 15 DODATKOWYCH znaczących terminów, akronimów, żargonu lub pojęć z tekstu.
- Jeśli ta książka jest non-fiction: wyodrębnij terminy techniczne, pojęcia, akronimy lub żargon.
- Jeśli ta książka jest fiction: wyodrębnij elementy budowy świata, takie jak frakcje, organizacje, systemy magii, technologie, stworzenia, języki lub wiedza wewnątrzświatowa.
Zwróć TYLKO poprawny obiekt JSON.

WYMÓG ZWIĘZŁOŚCI (KRYTYCZNY):
Aby uniknąć obcięcia odpowiedzi AI, utrzymuj definicje terminów poniżej {MAX_TERM_DEF} znaków.

KRYTYCZNA INSTRUKCJA:
NIE uwzględniaj żadnych z następujących terminów, ponieważ zostały już wyodrębnione:
%s

ŚCISŁE ZASADY DOTYCZĄCE SPOILERÓW:
- ABSOLUTNIE ŻADNYCH informacji spoza bieżącego postępu czytania. Zatrzymaj się dokładnie na %d%% postępu.

WYMAGANY FORMAT JSON:
{
  "terms": [
    {
      "name": "Termin lub Akronim",
      "expanded": "Pełne rozwinięcie lub to samo co nazwa",
      "category": "Frakcja / System magii / Technologia / Stworzenie / Organizacja / Wiedza / Język / Akronim / Termin techniczny / Pojęcie / Żargon",
      "definition": "Zwięzła definicja w kontekście (MAKS. {MAX_TERM_DEF} znaków)"
    }
  ]
}]],

     -- Targeted Single Word Lookup
     single_word_lookup = [[Użytkownik zaznaczył słowo "%s".
ZADANIE: Określ, czy to słowo reprezentuje postać, miejsce, postać historyczną lub termin techniczny/akronim w książce.

KRYTYCZNE DLA POSTACI I MIEJSC: Użyj dostarczonego "BOOK TEXT CONTEXT", aby zidentyfikować byt. Jeśli słowo jest podane jako wskazówka "SEARCH TARGET" lub "DIRECT REFERENCE", występuje ono w książce na bieżącej pozycji. Nie odrzucaj go tylko dlatego, że nie zostało dokładnie znalezione w podpróbkowanym tekście narracyjnym. Krótkie imiona (nawet 2-litowe, np. "Oz", "Al", "Jo") są poprawne i powinny być analizowane.
KRYTYCZNE DLA POSTACI HISTORYCZNYCH: MOŻESZ użyć swojej wewnętrznej wiedzy, aby zweryfikować ich tożsamość i podać biografię/rolę, TYLKO jeśli są prawdziwą, znaczącą postacią historyczną. MUSISZ jednak nadal użyć kontekstu tekstu dla ich znaczenia w książce.
KRYTYCZNE DLA TERMINÓW: Jeśli książka jest non-fiction, sprawdź, czy słowo jest terminem technicznym, akronimem lub kluczowym pojęciem. Podaj jego definicję w kontekście.
Jeśli słowo NIE jest postacią, miejscem, postacią historyczną ani terminem technicznym, ustaw `is_valid` na false.

WYMAGANY FORMAT JSON:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Pełne imię i nazwisko",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Krótka etykieta archetypu (3-5 słów, np. 'Antagonista', 'Protagonista', 'Ofiara')",
    "gender": "Mężczyzna/Kobieta/Nieznana",
    "occupation": "Zawód",
    "description": "Krótki opis (MAKS. 250 znaków)"
  },
  "error_message": ""
}

Uwaga: Jeśli typ to "location", element powinien zawierać "name" i "description". Jeśli typ to "historical_figure", element powinien zawierać "name", "biography" i "role". Jeśli typ to "term", element powinien zawierać "name", "expanded", "category" i "definition".

Jeśli `is_valid` jest false:
{
  "is_valid": false,
  "error_message": "Krótkie wyjaśnienie, dlaczego to nie jest postać, miejsce ani termin."
}]],

    -- Smart Merge Descriptions
    merge_descriptions = [[ZADANIE: Połącz następujące dwa opisy tego samego bytu (postaci lub miejsca) w jedno spójne i zwięzłe podsumowanie.
Usuń zbędne informacje i zapewnij naturalny przepływ końcowego opisu.

Opis główny: %s
Opis drugorzędny: %s

WYMAGANY FORMAT JSON:
{
  "merged_description": "Połączony i dopracowany opis (Maks. {MAX_CHAR_DESC} znaków)"
}]],

    -- Fallback strings
    fallback = {
        unknown_book = "Nieznana książka",
        unknown_author = "Nieznany autor",
        unnamed_character = "Nienazwana postać",
        not_specified = "Nie określono",
        no_description = "Brak opisu",
        unnamed_person = "Nienazwana osoba",
        no_biography = "Brak dostępnej biografii"
    }
}