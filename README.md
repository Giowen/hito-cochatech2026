# Hito — Copiloto Inmobiliario

> **Salesforce + Zillow + DocuSign-Lite para el agente inmobiliario latinoamericano, empezando por el único mercado con anticrético.**

**Hackathon CochaTech 2026** · Team Tokenizers · Categoría empresarial · Reto INTERSIM TECH Desafío 2

---

## ¿Qué es Hito?

Ecosistema dual de IA para inmobiliarias bolivianas que:

1. **Matchmaking visual** cliente-propiedad en mapa con scoring por compatibilidad
2. **Valuación dinámica** con comparables ajustada por TC paralelo USD/Bs
3. **Due diligence de contratos** (compra-venta, alquiler, anticrético) con NLP

**Moat clave**: manejo nativo de anticrético, instrumento legal único de Bolivia, que incumbents extranjeros (HouseCanary, Reonomy, Zillow) no pueden replicar.

## Stack

- **Frontend**: Flutter Web (target principal) + Android
- **State**: flutter_riverpod
- **Maps**: flutter_map + OpenStreetMap tiles (gratis vs Google Maps)
- **AI**: Groq (Llama 3.3 70B + Whisper v3) — 10x más barato y 5x más rápido que GPT/Claude
- **HTTP**: dio (streaming nativo)
- **Local storage**: in-memory + JSON assets (hardcoded seed para demo)

## Quick start

```bash
cd hito
cp .env.example .env
# Pegar tu GROQ_API_KEY real en .env
flutter pub get
flutter run -d chrome --web-port 8080
```

## Phase 0 — Stack Validation Decision Point

**Fecha**: Sábado 16 May 2026

| Test | Status | Notes |
|---|---|---|
| Test 1: flutter_map + OSM | ✓ PASS | Cochabamba renders, zoom fluido |
| Test 2: record audio HTTPS | ✓ PASS | Audio captured con permiso del browser |
| Test 3: Groq streaming | ✓ PASS | First token 662ms (target <2000ms) |
| Test 4: flutter_map_heatmap | ⚠ FALLBACK | Rendering bugs en zoom (cuadrado negro, points azules). Adopted polygon fallback per PRD §12 |

**Decisión**: 3/4 PASS + heatmap → polygon zones (mismo wow visual, sin jank, sin riesgo). Avanzamos con full plan.

## Roadmap

- **Phase 1**: Matchmaking core (data models, Groq client, match list UI)
- **Phase 2**: Map + Acto 1 wow (markers coloreados, voice input, AI streaming, polygon zones)
- **Phase 3**: Valuación dinámica (TC paralelo, comparables, vista dual María/Juan)
- **Phase 4**: Due diligence de contratos (cláusulas coloreadas, gravamen check)
- **Phase 5**: Integración + polish + backup video
- **Phase 6**: Sleep + dry run + ensayos del pitch

## Pitch

Domingo 17 May 2026, 11:00 AM. **3:00 exactos** + 2 min Q&A. Modalidad híbrida: Luis vía Zoom desde Oruro, admins presencial en Cochabamba.

## License

MIT — ver [LICENSE](./LICENSE).
