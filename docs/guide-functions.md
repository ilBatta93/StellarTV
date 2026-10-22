// Guida ufficiale StellarTV. Va aggiornata insieme a ogni modifica di funzioni
// dell'app o del sito, includendo solo funzioni attive nella versione corrente.
// Testi neutri: nessun riferimento a fornitori, formati di sorgente o tipi di contenuto.
// Versione app: 3.6.8

export type GuideItem = { title: string; body: string[] };
export type GuideSection = { id: string; title: string; intro: string; items: GuideItem[] };

export const GUIDE: GuideSection[] = [
  {
    id: "inizio",
    title: "Per iniziare",
    intro: "Installazione, primo avvio e aggiornamenti.",
    items: [
      { title: "Dispositivi supportati", body: ["StellarTV funziona su TV Android, Google TV e Fire TV, su telefoni e tablet Android e su iPhone e iPad.", "Sulla TV l'interfaccia è pensata per il telecomando, sul telefono per il tocco."] },
      { title: "Scaricare l'app", body: ["Dalla Panoramica del sito trovi i pulsanti di download, sempre all'ultima versione.", "Sulla TV puoi usare gli indirizzi brevi /apk e /ipa del sito, che funzionano anche senza accesso."] },
      { title: "Primo avvio", body: ["Dopo l'animazione del logo compare la schermata di accesso. Su TV la tastiera si apre premendo OK sul campo, su telefono con un tocco."] },
      { title: "Aggiornare l'app", body: ["Installa la nuova versione sopra quella esistente: preferiti, cronologia, stati di visione e Filtro Bambino restano intatti.", "Dopo ogni aggiornamento la Panoramica del sito elenca cosa controllare."] },
    ],
  },
  {
    id: "account",
    title: "Account e accesso",
    intro: "Accedere, uscire e gestire i dispositivi.",
    items: [
      { title: "Accedere sulla TV con il telefono", body: ["Sulla TV scegli Accedi con il telefono: compaiono un QR e un codice.", "Inquadra il QR oppure apri Collega TV sul sito e inserisci il codice. Conferma e la TV entra da sola. La password non passa mai dalla TV e il codice vale una sola volta."] },
      { title: "Password dimenticata", body: ["Nella schermata di accesso scegli Password dimenticata e segui il collegamento ricevuto via email."] },
      { title: "Durata dell'accesso sul sito", body: ["Nell'Account del sito scegli quanto resta valido l'accesso nel browser. Vale dal login successivo e non disconnette mai app o TV."] },
      { title: "Uscire", body: ["Dalle Impostazioni dell'app esci e torni alla schermata di accesso.", "Dal sito puoi uscire dal browser o scegliere Disconnetti tutti i dispositivi."] },
      { title: "Dispositivi collegati", body: ["L'Account del sito mostra gli accessi attivi con tipo e modello. L'elenco si carica all'apertura; premi Aggiorna per rileggerlo."] },
    ],
  },
  {
    id: "chiave",
    title: "Chiave di recupero e cassaforte",
    intro: "Come sono protetti i tuoi dati.",
    items: [
      { title: "La cassaforte", body: ["Preferiti, cronologia, stati di visione e dati di configurazione sono salvati cifrati: il cloud conserva solo dati illeggibili."] },
      { title: "Uso locale", body: ["Puoi usare i dati salvati sul dispositivo senza attivare la cassaforte. Per sincronizzarli occorre la chiave; senza chiave i tentativi sul salvataggio cifrato si fermano prima della rete."] },
      { title: "La chiave di recupero", body: ["Sblocca la cassaforte su un nuovo dispositivo. Conservala in un posto sicuro, ad esempio un gestore di password: senza di essa nessuno può recuperare i dati."] },
      { title: "Inviare la chiave alla TV", body: ["Sulla TV scegli di ricevere la chiave: compare un QR. Inquadralo col telefono, incolla la chiave e invia.", "Il trasferimento è cifrato tra i due dispositivi, scade dopo 2 minuti e viene cancellato appena letto. Allo stesso modo puoi inviare i dati di configurazione senza digitarli col telecomando."] },
      { title: "Cassaforte dal sito", body: ["Nell'Account sblocchi la cassaforte con la chiave per consultare i tuoi dati. La chiave resta solo nella pagina e sparisce quando la chiudi."] },
    ],
  },
  {
    id: "home",
    title: "Home e navigazione",
    intro: "Righe, ricerca, preferiti e personalizzazione.",
    items: [
      { title: "La Home", body: ["Mostra banner, righe di titoli, ultimi aggiunti e Continua a guardare, con loghi ufficiali e percentuale di visione.", "Sulla TV le righe scorrono col D-Pad e il riquadro selezionato resta sempre visibile."] },
      { title: "Continua a guardare", body: ["Quando superi la soglia di visione, il titolo resta nella riga con la scritta Prossimo se esiste un episodio ancora da vedere: OK lo avvia.", "Quando hai visto tutti gli episodi, o rimuovi il titolo dalla cronologia, la locandina sparisce."] },
      { title: "Personalizzare", body: ["Nelle Impostazioni scegli numero e forma delle locandine, orientamento della Home, scala dell'interfaccia, soglia di visione e ordine delle righe. Queste scelte si sincronizzano tra i dispositivi."] },
      { title: "Categorie, filtri e ricerca", body: ["Apri i pannelli Categorie e Filtri per piattaforma, genere e ordinamento. Cerca raggiunge tutte le sezioni. Tutto si usa col telecomando."] },
      { title: "Preferiti", body: ["Aggiungi un titolo ai preferiti dalla sua scheda. Le rimozioni sono definitive su tutti i dispositivi."] },
    ],
  },
  {
    id: "cronologia",
    title: "Cronologia",
    intro: "Rivedere e pulire ciò che hai guardato.",
    items: [
      { title: "Voci raggruppate", body: ["Gli episodi dello stesso titolo occupano una sola riga, raggiungibile con una pressione di Su o Giù. OK apre il titolo."] },
      { title: "Menu rapido", body: ["Tieni premuto OK su una riga: puoi Aprire, Mostrare o nascondere gli episodi e Rimuovere.", "Rimuovere il titolo cancella tutti i suoi episodi; dall'elenco episodi puoi rimuoverne uno solo."] },
    ],
  },
  {
    id: "titoli",
    title: "Schede titolo",
    intro: "Dettagli, trailer, episodi e stati di visione.",
    items: [
      { title: "Scheda", body: ["Trama, valutazioni, cast e azioni in fila: Riproduci, Trailer, Preferiti."] },
      { title: "Trailer", body: ["Si apre in YouTube, in italiano quando disponibile, altrimenti in inglese. Non entra nella cronologia."] },
      { title: "Episodi", body: ["Stagioni ed episodi scorrono in orizzontale con la percentuale di visione. Se manca la miniatura viene usata l'immagine del titolo."] },
      { title: "Gestisci visione", body: ["Scegli una stagione e apri la riga da modificare: Visto, Non visto oppure Automatico dal progresso. Le azioni per tutta una stagione o l’intera raccolta sono nei rispettivi menu separati.", "Le scelte sono reversibili e si sincronizzano. Automatico dal progresso rimuove la scelta manuale senza cancellare la posizione salvata.", "Se inizi da una stagione successiva, un suggerimento discreto propone di segnare le precedenti; Non ora lo silenzia."] },
    ],
  },
  {
    id: "player",
    title: "Player",
    intro: "Tutti i tasti durante la riproduzione.",
    items: [
      { title: "Avvio pulito", body: ["Il video parte senza comandi sullo schermo."] },
      { title: "OK: pausa e comandi", body: ["Una pressione di OK mette in pausa e mostra i comandi. Premi di nuovo Play per riprendere; i comandi spariscono da soli."] },
      { title: "Destra e Sinistra", body: ["A comandi nascosti fanno avanzare o riavvolgere senza mostrare la barra."] },
      { title: "Su: informazioni", body: ["Mostra in alto titolo, trama, tempo rimanente e ora di fine stimata. Sparisce dopo qualche secondo o con Indietro."] },
      { title: "Giù: pannello rapido", body: ["Apre dal basso Audio, Sottotitoli e, quando disponibili, Stagioni ed episodi."] },
      { title: "Audio e sottotitoli", body: ["Dai rispettivi pannelli scegli traccia, lingua e sincronizzazione. I sottotitoli mancanti vengono cercati verificando episodio e lingua."] },
      { title: "Barra dei comandi", body: ["Contiene qualità, velocità, formato immagine e motore di riproduzione. Le impostazioni tecniche restano proprie di ogni dispositivo."] },
      { title: "Salta sigla", body: ["Quando compare è già selezionato: premi OK e il video salta senza mostrare i comandi.", "Gli intervalli vengono verificati rispetto alla durata. Dove disponibili si usano anche i capitoli incorporati con il motore mpv. Il riconoscimento non è garantito per tutti i titoli."] },
      { title: "Passaggio automatico", body: ["Apri Impostazioni › Player › Riproduzione. Sulla TV scegli prima il profilo delle riproduzioni con episodi. Attiva o disattiva Passa automaticamente al prossimo episodio; inizialmente è attivo.", "Se disattivo, il prossimo episodio parte solo quando lo scegli. La scelta si sincronizza insieme alle preferenze comuni quando la cassaforte è attiva e non cambia la diretta."] },
      { title: "Coda e prossimo episodio", body: ["Con una coda verificata e il passaggio automatico attivo compare un conto alla rovescia di cinque secondi. In pausa, con un pannello aperto o fuori dall'app il conteggio si ferma. Guarda Crediti annulla il passaggio per quella riproduzione.", "Senza una coda verificata, negli ultimi 90 secondi di una riproduzione di almeno cinque minuti può comparire un suggerimento manuale: non provoca salti anticipati. Il passaggio automatico, se attivo, resta possibile alla fine effettiva."] },
      { title: "Ripresa", body: ["La cronologia conserva l’ultima posizione effettiva anche dopo un riavvio o uno spostamento avanti o indietro. Cambia solo la voce che stai riproducendo, non le altre."] },
      { title: "Nessuna interruzione", body: ["Durante la visione non parte nessun aggiornamento pesante: viene rimandato alla chiusura del player."] },
    ],
  },
  {
    id: "diretta",
    title: "Diretta",
    intro: "Canali, guida programmi e MultiView.",
    items: [
      { title: "Cambiare canale", body: ["Durante la diretta Su e Giù passano al canale precedente o successivo. Sinistra apre l'elenco trasparente dei canali, con i recenti in cima; Indietro lo chiude."] },
      { title: "Guida programmi", body: ["Mostra il programma in corso e i successivi."] },
      { title: "MultiView", body: ["Guarda più canali in riquadri; sposta il focus col D-Pad per scegliere l'audio."] },
      { title: "Pausa e riascolto", body: ["Dove disponibile puoi mettere in pausa, rivedere programmi passati e registrare."] },
    ],
  },
  {
    id: "bambino",
    title: "Filtro Bambino",
    intro: "Un ambiente sicuro per i più piccoli.",
    items: [
      { title: "Come funziona", body: ["Mostra solo titoli adatti in base a generi e classificazioni d'età. Se un titolo non è verificabile viene nascosto.", "Si attiva dalle Impostazioni e vale su tutti i dispositivi."] },
    ],
  },
  {
    id: "telecomando",
    title: "Telecomando",
    intro: "Ogni funzione si usa con D-Pad, OK e Indietro.",
    items: [
      { title: "Tasti principali", body: ["Frecce: spostano il focus. OK: apre o conferma; tenuto premuto apre il menu rapido dove disponibile. Indietro: chiude pannelli e torna indietro."] },
      { title: "Menu in alto", body: ["Dalla prima riga premi Su per raggiungere il menu: torni sempre alla scheda attiva."] },
      { title: "Indietro dalla Home", body: ["Nelle Impostazioni scegli se il doppio Indietro manda l'app in secondo piano o la chiude."] },
    ],
  },
  {
    id: "sync",
    title: "Sincronizzazione e risparmio",
    intro: "Cosa viaggia tra i dispositivi e quando.",
    items: [
      { title: "Cosa si sincronizza", body: ["Preferiti, cronologia, stati di visione, dati di configurazione e preferenze di aspetto. Il passaggio automatico è una preferenza comune; le impostazioni tecniche del player restano locali."] },
      { title: "Quando", body: ["Ogni modifica viene salvata subito sul dispositivo e inviata al cloud; durante la visione l'invio avviene alla pausa o alla chiusura.", "Se il cloud non risponde, l'app riprova con pause via via più lunghe senza perdere nulla."] },
      { title: "Ibernazione", body: ["Quando l'app è in secondo piano o lo schermo è spento, le attività automatiche si fermano e riprendono al ritorno."] },
    ],
  },
  {
    id: "sito",
    title: "Il sito",
    intro: "Cosa puoi fare dal browser.",
    items: [
      { title: "Panoramica", body: ["Download dell'app, ultima versione e controlli dopo l'aggiornamento."] },
      { title: "Collega TV", body: ["Inserisci il codice mostrato dalla TV per farla accedere."] },
      { title: "Account", body: ["Dispositivi, durata dell'accesso, cassaforte e Log errori."] },
      { title: "Riservatezza", body: ["Il sito non è indicizzato dai motori di ricerca."] },
    ],
  },
  {
    id: "diagnostica",
    title: "Problemi e diagnostica",
    intro: "Cosa fare quando qualcosa non va.",
    items: [
      { title: "Inviare un report", body: ["Nell'app apri Diagnostica, scegli il tipo di problema e invia. Contiene solo dati tecnici, mai password o chiavi. I report compaiono in Account › Log errori, dove puoi eliminarli."] },
      { title: "Verifica servizio", body: ["Apri Impostazioni › Diagnostica, scegli la scheda appropriata e premi Verifica servizio. Dopo un errore finale il controllo compare anche nella schermata di riproduzione.", "È un controllo locale singolo, con attesa massima di otto secondi: non usa il cloud e non ripete richieste in continuazione. Non è disponibile per tutti i tipi di accesso.", "Il risultato distingue accesso non attivo, limite di connessioni, server raggiungibile e risposta non verificabile. Il conteggio può includere questa riproduzione o una connessione appena chiusa: non dimostra che sia collegato un altro dispositivo. Un timeout non dimostra che il server sia offline."] },
      { title: "Il video non parte", body: ["Leggi il risultato della verifica, controlla la rete e usa Riprova oppure Prova con un altro motore. Un servizio raggiungibile non garantisce la disponibilità di ogni riproduzione."] },
      { title: "Schermata di attesa", body: ["All’avvio puoi navigare usando la copia salvata senza aspettare il recupero cloud. Il primo caricamento mostra indicatori nelle sezioni; durante un aggiornamento completo resta una schermata di attesa protettiva."] },
      { title: "Dati assenti su un nuovo dispositivo", body: ["Accedi con lo stesso account e inserisci la chiave di recupero."] },
    ],
  },
];
