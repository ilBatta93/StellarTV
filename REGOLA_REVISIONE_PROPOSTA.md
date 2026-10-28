# Proposta revisione regole StellarTV — 28/10/2026
# Modalità: Agent — modifiche pronte su richiesta utente
# Lingua: italiano, terminologia neutra (nessun termine vietato)

## 1. .cursorrules (master, 7 sezioni)
- Stato: VIGENTE — nessuna rimozione
- Proposta: AGGIUNGERE nota esplicita in sez. 1 (termini vietati anche nei commenti di codice .dart)
- Proposta: AGGIORNARE sez. 7 — citare serie 3.8.N e docs/release-current.md come unica fonte pubblica

## 2. .cursor/rules/android-build.mdc
- Stato: VIGENTE
- Proposta: NESSUN CAMBIO — workflow GitHub resta obbligatorio

## 3. AGENTS.md (app)
- Stato: VIGENTE
- Proposta: AGGIUNGER linea su "Regole .cursor/rules/*.mdc si applicano solo se file nel lavoro" (già presente ma rafforzare)
- Proposta: AGGIORNARE elenco aree: aggiungere diagnostics, live-guide, sync-account

## 4. catalog-data.mdc
- Stato: VIGENTE — molto specifico su NDJSON, isolate, cache
- Proposta: AGGIORNARE: menzionare che la lettura NDJSON v3 resta in streaming anche con sezioni >500 titoli (rafforzare)
- Proposta: RIMUOVERE solo se passiamo a formato diverso (non ora)

## 5. diagnostics.mdc
- Stato: VIGENTE — event `clock_pinned`, telemetria frame, export v3
- Proposta: AGGIORNARE: specificare che `suspected_stall` usa `frameDelta` nativo Exo/mpv (già presente, confermare)
- Proposta: NESSUN RIMOZIONE

## 6. history.mdc
- Stato: VIGENTE — soglia 94%, ripresa serie, cronologia cifrata
- Proposta: AGGIORNARE: aggiungere che il completamento manuale usa record versionati nel profilo (già presente, precisare con timestamp UTC)
- Proposta: RIMUOVERE solo se si elimina la cronologia locale (no)

## 7. live-guide.mdc
- Stato: VIGENTE — guida EPG, timeline 56 px, canali timeshift sepa
- Proposta: AGGIORNARE: precisare che i canali con +1/+2 restano separati anche se tvg-id condiviso (già presente, confermare)
- Proposta: NESSUN RIMOZIONE

## 8. metadata-kids.mdc
- Stato: VIGENTE — PIN bambino, voti IMDb > TMDB, logo it/en solo
- Proposta: AGGIORNARE: specificare che un IMDb in attesa resta nascosto (già presente, ribadire)
- Proposta: AGGIORNARE filtro bambino: generi bloccati (Horror, Thriller, Crime, Action, Romance, Reality, News, Drama) — confermare elenco
- Proposta: RIMUOVERE solo se si elimina il profilo bambino (no)

## 9. mobile-touch.mdc
- Stato: VIGENTE ma MINIMALE (solo layout touch separato)
- Proposta: AGGIORNARE con dettagli touch della scheda titolo se necessario
- Proposta: RIMUOVERE se si unifica touch/TV sotto unica regola (valutare migrazione verso tv-ui.mdc)

## 10. player.mdc
- Stato: VIGENTE — molto denso (Exo/mpv, seek, MultiView, sigla, buffer)
- Proposta: AGGIORNARE: confermare che freccia sinistra in diretta apre elenco canali senza interrompere riproduzione (già in .cursorrules sez. 3, verificare coerenza)
- Proposta: AGGIORNARE: aggiungere nota su "tasto OK comandi nascosti = pausa + apri comandi" (già presente, ribadire)
- Proposta: NESSUN RIMOZIONE — regola core

## 11. sync-account.mdc
- Stato: VIGENTE — vault AES-256-GCM, sync account, preferiti tombstone
- Proposta: AGGIORNARE: precisare che la chiave di recupero STV1-[64 hex] non va nel cloud (già presente, confermare)
- Proposta: AGGIORNARE: aggiungere nota su disconnessione remota ritirata (polling rimosso, già presente)
- Proposta: RIMUOVERE solo se si abbandona il vault cifrato (no)

## 12. tv-ui.mdc
- Stato: VIGENTE — focus D-Pad, Home, griglie, banner, transizioni
- Proposta: AGGIORNARE: confermare che il focus usa anello 2,5 px nel colore di accento, senza blur (già presente, ribadire)
- Proposta: AGGIORNARE: specificare che la memoria immagini TV scende a ~80 voci / 24 MB sotto pressione (già presente, confermare)
- Proposta: NESSUN RIMOZIONE

## 13. Companion web (stellartv-ae76efd2)
- .cursorrules web: solo riferimento AGENTS.md — CONFERMARE
- .cursor/rules/workflow.mdc: commit/push — CONFERMARE
- AGENTS.md web: manuale Lovable — AGGIORNARE se cambiano endpoint API o schema Supabase

## Azioni proposte (ordine)
1. Confermare tutte le regole app (nessuna rimozione immediata)
2. Aggiornare .cursorrules sez. 7 e nota terminologia
3. Aggiornare AGENTS.md con elenco aree completo
4. Valutare fusione mobile-touch.mdc in tv-ui.mdc (opzionale)
5. Aggiornare docs/release-current.md dopo modifiche
6. Creare commit + push (regola AGENTS.md / workflow.mdc)

---
Nota: tutto in italiano, terminologia neutra. Nessun riferimento a IPTV, m3u, provider, abbonamenti o copyright.
