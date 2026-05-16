-- ============================================================================
-- Hito · Seed data (2026-05-16) — 12 propiedades canónicas claude-design
-- ============================================================================
-- Ejecutar DESPUÉS de la migration. Idempotente vía ON CONFLICT DO NOTHING.
-- ============================================================================

INSERT INTO properties (
  id, address, title, lat, lng, neighborhood,
  price_bob, price_usd_paralelo, area_m2, lot_m2,
  bedrooms, bathrooms, parking,
  type, listing_mode, supported_transactions, anticretico_bob,
  year_built, age_years, amenities, photos, cochabamba_tags,
  ai_notes, compatibility, listed_days, agent_name, image,
  listing_status, description, has_lien
) VALUES
-- p01 — STAR del demo (96% compat, has_lien para Acto 3 Banco BISA)
('p01',
 'Av. Pando #1842, Cala Cala, Cochabamba',
 'Casa familiar — Av. Pando',
 -17.388, -66.158, 'cala_cala',
 2623000, 215000, 280, 320,
 4, 3, 2,
 'casa', 'venta', ARRAY['venta','anticretico']::TEXT[], 320000,
 2018, 8,
 ARRAY['patio','garage','vigilancia_zona']::TEXT[],
 ARRAY[]::TEXT[],
 ARRAY[]::TEXT[],
 ARRAY[
   'Coincide en zona de mayor seguridad (índice Cala Cala 8.7/10).',
   '14 min al colegio Calvert. 11 min a la oficina por Av. América.',
   'Patio de 180 m² — los tres puntos que mencionaste sobre tu hija.'
 ]::TEXT[],
 96, 9, 'María Quiroga', 'gradient-1',
 'activa',
 'Casa familiar en Cala Cala con 4 dormitorios, 3 baños, garage doble y patio amplio. Año 2018.',
 TRUE),

('p02',
 'Edif. Torres del Sur, Recoleta, Cochabamba',
 'Departamento con vista — Edif. Torres del Sur',
 -17.376, -66.140, 'recoleta',
 2171600, 178000, 165, NULL,
 3, 2, 2,
 'departamento', 'venta', ARRAY['venta']::TEXT[], NULL,
 2022, 4,
 ARRAY['ascensor','gym','vista_panoramica']::TEXT[],
 ARRAY[]::TEXT[], ARRAY[]::TEXT[],
 ARRAY[
   'Excelente para Sofía y Mateo (cerca colegios).',
   'Piso 8 — sin tráfico al frente.'
 ]::TEXT[],
 89, 14, NULL, 'gradient-2',
 'activa',
 'Departamento moderno piso 8 en Recoleta con vista panorámica, 3 dorm, 2 garages.',
 FALSE),

('p03',
 'Calle Ladislao Cabrera, Queru Queru, Cochabamba',
 'Casa con jardín — Ladislao Cabrera',
 -17.382, -66.143, 'queru',
 2379000, 195000, 240, 380,
 4, 3, 2,
 'casa', 'venta', ARRAY['venta','anticretico']::TEXT[], 280000,
 2015, 11,
 ARRAY['jardin_amplio','garage','patio_trasero']::TEXT[],
 ARRAY[]::TEXT[], ARRAY[]::TEXT[],
 ARRAY[
   'Patio amplio + zona tranquila.',
   'Calle sin salida — menos tráfico para los niños.'
 ]::TEXT[],
 92, 21, NULL, 'gradient-3',
 'activa',
 'Casa de 4 dormitorios con jardín grande en Queru Queru, calle sin salida.',
 FALSE),

('p04',
 'Av. Beijing, Tupuraya, Cochabamba',
 'Casa moderna — Av. Beijing',
 -17.395, -66.155, 'tupuraya',
 1732400, 142000, 195, 240,
 3, 2, 2,
 'casa', 'venta', ARRAY['venta']::TEXT[], NULL,
 2020, 6,
 ARRAY['garage','patio']::TEXT[],
 ARRAY[]::TEXT[], ARRAY[]::TEXT[],
 ARRAY[
   'Precio 12% por debajo del comparable de zona.',
   '21 min a tu oficina — ligeramente por encima de tu objetivo.'
 ]::TEXT[],
 81, 6, NULL, 'gradient-4',
 'activa',
 'Casa moderna 2020 en Tupuraya. Bien valuada, ligeramente lejos de Recoleta.',
 FALSE),

('p05',
 'Las Palmas, Cocha Norte, Cochabamba',
 'Casa de campo — Las Palmas',
 -17.358, -66.140, 'norte',
 3269600, 268000, 340, 720,
 5, 4, 3,
 'casa', 'venta', ARRAY['venta','anticretico']::TEXT[], 410000,
 2019, 7,
 ARRAY['piscina','jardin_grande','quincho','garage_triple']::TEXT[],
 ARRAY[]::TEXT[], ARRAY[]::TEXT[],
 ARRAY[
   'Excede tu rango por $18k.',
   'Trayecto a la oficina supera tu límite (28 min).'
 ]::TEXT[],
 64, 38, NULL, 'gradient-5',
 'activa',
 'Casa de campo lujosa en Cocha Norte con piscina y lote grande. Sobre presupuesto.',
 FALSE),

('p06',
 'Pacata Alta, Cochabamba',
 'Casa con terraza — Pacata Alta',
 -17.420, -66.170, 'pacata',
 0, 0, 175, 220,
 3, 2, 1,
 'casa', 'anticretico', ARRAY['anticretico']::TEXT[], 180000,
 2017, 9,
 ARRAY['terraza','patio']::TEXT[],
 ARRAY[]::TEXT[], ARRAY[]::TEXT[],
 ARRAY[
   'Solo anticrético — no es opción de compra.',
   'Buena zona pero algo lejos de los colegios.'
 ]::TEXT[],
 58, 32, NULL, 'gradient-6',
 'activa',
 'Casa con terraza solo en modalidad anticrético en Pacata Alta.',
 FALSE),

('p07',
 'Av. Petrolera, Sarco, Cochabamba',
 'Casa de dos plantas — Av. Petrolera',
 -17.408, -66.165, 'sarco',
 1512800, 124000, 168, 200,
 3, 2, 1,
 'casa', 'venta', ARRAY['venta']::TEXT[], NULL,
 2014, 12,
 ARRAY['dos_plantas','garage']::TEXT[],
 ARRAY[]::TEXT[], ARRAY[]::TEXT[],
 ARRAY[
   'Buen precio pero requiere refacción de cocina (~$8k).',
   'Zona en crecimiento.'
 ]::TEXT[],
 73, 47, NULL, 'gradient-7',
 'activa',
 'Casa de dos plantas en Sarco, buen precio, requiere refacción.',
 FALSE),

('p08',
 'Edif. Cordillera, Cala Cala, Cochabamba',
 'Penthouse — Edif. Cordillera',
 -17.388, -66.160, 'cala_cala',
 3599000, 295000, 280, NULL,
 4, 4, 3,
 'departamento', 'venta', ARRAY['venta']::TEXT[], NULL,
 2023, 3,
 ARRAY['penthouse','terraza_panoramica','gym','ascensor']::TEXT[],
 ARRAY[]::TEXT[], ARRAY[]::TEXT[],
 ARRAY[
   'Por encima de rango.',
   'No tiene patio — criterio importante para tu hija.'
 ]::TEXT[],
 41, 67, NULL, 'gradient-8',
 'activa',
 'Penthouse premium en Cala Cala. Sobre presupuesto, sin patio.',
 FALSE),

('p09',
 'Calle España, Centro, Cochabamba',
 'Casa colonial restaurada — calle España',
 -17.395, -66.157, 'centro',
 2049600, 168000, 220, 280,
 3, 2, 0,
 'casa', 'venta', ARRAY['venta','anticretico']::TEXT[], 240000,
 1958, 68,
 ARRAY['patio_colonial','restaurada_2021']::TEXT[],
 ARRAY[]::TEXT[], ARRAY[]::TEXT[],
 ARRAY[
   'Sin parqueo — criterio bloqueante para ti.',
   'Patio interno colonial — encantador pero ruidoso.'
 ]::TEXT[],
 52, 18, NULL, 'gradient-9',
 'activa',
 'Casa colonial 1958 restaurada en 2021. Centro histórico. Sin parqueo.',
 FALSE),

('p10',
 'Tiquipaya, Cochabamba',
 'Casa de campo — Tiquipaya',
 -17.337, -66.207, 'tiquipaya',
 1927600, 158000, 260, 520,
 4, 3, 3,
 'casa', 'venta', ARRAY['venta']::TEXT[], NULL,
 2021, 5,
 ARRAY['jardin_grande','garage_triple']::TEXT[],
 ARRAY[]::TEXT[], ARRAY[]::TEXT[],
 ARRAY[
   'Trayecto a oficina excede tu límite (32 min sin tráfico).',
   'Zona en plusvalía.'
 ]::TEXT[],
 38, 22, NULL, 'gradient-10',
 'activa',
 'Casa de campo en Tiquipaya con lote grande. Lejos de Recoleta.',
 FALSE),

('p11',
 'Av. Salamanca, Queru Queru, Cochabamba',
 'Casa esquinera — Av. Salamanca',
 -17.382, -66.145, 'queru',
 2293600, 188000, 230, 290,
 4, 3, 2,
 'casa', 'venta', ARRAY['venta','anticretico']::TEXT[], 290000,
 2016, 10,
 ARRAY['esquinera','garage_doble','orientacion_norte']::TEXT[],
 ARRAY[]::TEXT[], ARRAY[]::TEXT[],
 ARRAY[
   'Cumple los 4 criterios principales.',
   'Esquina con buena luz — orientación norte.'
 ]::TEXT[],
 87, 11, NULL, 'gradient-11',
 'activa',
 'Casa esquinera en Av. Salamanca, orientación norte, garage doble.',
 FALSE),

('p12',
 'Villa Busch, Cochabamba',
 'Casa con local comercial — Villa Busch',
 -17.418, -66.135, 'villa_busch',
 1634800, 134000, 180, 200,
 3, 2, 1,
 'casa', 'venta', ARRAY['venta']::TEXT[], NULL,
 2010, 16,
 ARRAY['local_comercial']::TEXT[],
 ARRAY[]::TEXT[], ARRAY[]::TEXT[],
 ARRAY[
   'Tiene local comercial — no buscas eso.',
   'Por debajo de presupuesto pero requiere remodelación.'
 ]::TEXT[],
 32, 89, NULL, 'gradient-12',
 'activa',
 'Casa mixta con local comercial en Villa Busch. Buen precio.',
 FALSE)
ON CONFLICT (id) DO NOTHING;

-- Verificación: debería retornar 12.
-- SELECT COUNT(*) FROM properties;
