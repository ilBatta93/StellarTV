# .github/ — workflow

Regole d'area per Claude e Grok. Valgono anche il master `C:\Progetti\AGENTS.md`, l'`AGENTS.md` della radice e i `CLAUDE.md` delle cartelle superiori.

## Workflow
| File | Nome | Avvio |
| --- | --- | --- |
| `verify.yml` | StellarTV Verifica (senza rilascio) | automatico |
| `build.yml` | StellarTV Android Release | solo con «fai build android» |
| `build-ios.yml` | StellarTV iOS Release (Unsigned) | solo su richiesta esplicita |
| `keep-alive.yml` | Keep database awake (ping a Supabase) | pianificato, ogni giorno |

## Leggere gli esiti
- In `verify.yml` gli step di controllo hanno `continue-on-error`: il loro esito è sempre verde. Fa fede l'esito della run (step «Esito finale») o l'annotazione «Esiti» (`analyze=… format=… checks=… tests=…`).
- Annotazioni: `gh api repos/ilBatta93/StellarTV/check-runs/<job id>/annotations`.

## Regole
- `build.yml` ha `concurrency: android-release`: mai due build in coda insieme.
- I segreti si leggono solo da `secrets.*`; mai stampati nei log, mai scritti in file versionati.
- La versione si calcola dal numero di run (`3.8.<run - 110>`): non cambiarla a mano.
- I rilasci pubblici vanno anche su `ilBatta93/StellarTV-releases`, da cui il sito serve `/apk` e `/ipa`.
- Un workflow modificato si prova con una run di `verify.yml`, non con una build di rilascio.
