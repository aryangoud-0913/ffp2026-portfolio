-- ============================================================
-- FFP PORTFOLIO — SUPABASE SCHEMA
-- Mesa School of Business · 2026
-- Run this entire file in Supabase SQL Editor
-- ============================================================

-- Enable UUID generation
create extension if not exists "pgcrypto";


-- ============================================================
-- TABLE 1: cohorts
-- ============================================================
create table public.cohorts (
  id             uuid primary key default gen_random_uuid(),
  year           integer not null,
  cohort_number  integer not null check (cohort_number between 1 and 10),
  cohort_name    text not null,
  start_date     date not null,
  end_date       date not null,
  created_at     timestamptz not null default now(),
  unique (year, cohort_number)
);

comment on table public.cohorts is 'One row per cohort. 3 cohorts per year in 2026.';


-- ============================================================
-- TABLE 2: students (CORE TABLE — all 15 Excel fields)
-- ============================================================
create table public.students (
  id                   uuid primary key default gen_random_uuid(),
  cohort_id            uuid not null references public.cohorts(id) on delete restrict,

  -- URL slug — used in portfolio URL: ffp.mesa.edu/[slug]
  slug                 text not null unique,

  -- ── Personal Info (Excel fields 1–3) ──
  full_name            text not null,
  email                text not null,
  phone                text not null,          -- stored, never shown publicly
  gender_pronoun       text not null default 'she/her'
                         check (gender_pronoun in ('she/her', 'he/him', 'they/them')),
  photo_url            text,                   -- Google Drive direct URL

  -- ── Product / Proof of Work (Excel fields 4–7) ──
  product_name         text not null,
  product_description  text not null,
  product_photo_url    text,                   -- Google Drive direct URL
  revenue              numeric(12,2) not null default 0,
  customers_reached    integer not null default 0,
  markets_attended     integer not null default 0,

  -- ── Digital Presence (Excel fields 8–9) ──
  website_url          text,
  instagram_handle     text,                   -- without @

  -- ── Event Photos (Excel fields 14–15) ──
  -- Arrays of 1–3 Google Drive URLs per event
  flea_market_photos   text[] not null default '{}',
  demo_day_photos      text[] not null default '{}',

  -- ── Certificate (Excel field 11) ──
  certificate_url      text,                   -- Google Drive URL to signed PDF

  -- ── Publishing control ──
  -- Portfolio invisible until staff flips this to true
  is_published         boolean not null default false,

  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

comment on table public.students is 'One row per student. Core table. Staff fills via Supabase Studio.';
comment on column public.students.slug is 'Used in portfolio URL. Format: firstname-lastname-YYYY-cN e.g. priya-sharma-2026-c1';
comment on column public.students.phone is 'Stored for internal use only. Never exposed in portfolio frontend.';
comment on column public.students.gender_pronoun is 'Drives all copy on portfolio. she/her | he/him | they/them';
comment on column public.students.flea_market_photos is 'Array of 1–3 Drive URLs. Feeds into the carousel on portfolio.';
comment on column public.students.is_published is 'Set to true only when all data is complete and reviewed. Portfolio not visible until then.';

-- Auto-update updated_at on any row change
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger students_updated_at
  before update on public.students
  for each row execute function public.set_updated_at();


-- ============================================================
-- TABLE 3: assets (Excel field 10 — creatives)
-- One row per asset. Staff adds/removes individually.
-- ============================================================
create table public.assets (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references public.students(id) on delete cascade,

  asset_type    text not null
                  check (asset_type in (
                    'influencer_video',
                    'performance_video',
                    'static_ad'
                  )),

  url           text not null,           -- Google Drive direct URL
  thumbnail_url text,                    -- optional, for video preview
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now()
);

comment on table public.assets is 'Excel field 10. Every creative produced during FFP. One row per asset.';
comment on column public.assets.asset_type is 'influencer_video | performance_video | static_ad';
comment on column public.assets.sort_order is 'Controls display order within each asset_type group.';

create index assets_student_id_idx on public.assets(student_id);
create index assets_type_idx on public.assets(student_id, asset_type, sort_order);


-- ============================================================
-- TABLE 4: awards (Excel field 13 — OPTIONAL)
-- No rows for a student = awards section hidden entirely.
-- ============================================================
create table public.awards (
  id             uuid primary key default gen_random_uuid(),
  student_id     uuid not null references public.students(id) on delete cascade,

  award_title    text not null,
  award_subtitle text,
  badge_label    text not null,          -- "Winner" | "Top Performer" | "Runner Up"
  sort_order     integer not null default 0,
  created_at     timestamptz not null default now()
);

comment on table public.awards is 'Excel field 13. OPTIONAL. No rows = awards section hidden on portfolio.';

create index awards_student_id_idx on public.awards(student_id);


-- ============================================================
-- TABLE 5: notes (personalised messages — co-founder, mentor, peer)
-- 3 rows per student (one per note_type)
-- ============================================================
create table public.notes (
  id               uuid primary key default gen_random_uuid(),
  student_id       uuid not null references public.students(id) on delete cascade,

  note_type        text not null
                     check (note_type in ('cofounder', 'mentor', 'peer')),

  author_name      text not null,
  author_role      text not null,        -- e.g. "Co-founder, Mesa School of Business"
  author_photo_url text,                 -- Drive URL. Falls back to initials avatar if null.
  message          text not null,
  created_at       timestamptz not null default now(),

  -- Only one note per type per student
  unique (student_id, note_type)
);

comment on table public.notes is '3 personalised notes per student. cofounder + mentor + peer.';
comment on column public.notes.author_photo_url is 'Optional. Portfolio falls back to initials avatar if null.';

create index notes_student_id_idx on public.notes(student_id);


-- ============================================================
-- TABLE 6: ai_tools (Excel field 12 — STATIC per cohort)
-- Same tool list for all students in a cohort.
-- Set once, reused across all ~80 portfolios per cohort.
-- ============================================================
create table public.ai_tools (
  id          uuid primary key default gen_random_uuid(),
  cohort_id   uuid not null references public.cohorts(id) on delete cascade,

  tool_name   text not null,
  tool_use    text not null,             -- what FFP used it for
  logo_url    text,                      -- Drive URL to tool logo (for roulette animation)
  sort_order  integer not null default 0,

  unique (cohort_id, tool_name)
);

comment on table public.ai_tools is 'Excel field 12. Static per cohort — same tools taught to every student.';
comment on column public.ai_tools.logo_url is 'Used in the roulette/slot-machine animation on the portfolio.';

create index ai_tools_cohort_idx on public.ai_tools(cohort_id, sort_order);


-- ============================================================
-- TABLE 7: ai_tool_proficiency (junction — student × tool)
-- Per-student proficiency level for each AI tool.
-- 1 = Foundational · 2 = Proficient · 3 = Advanced
-- ============================================================
create table public.ai_tool_proficiency (
  id          uuid primary key default gen_random_uuid(),
  student_id  uuid not null references public.students(id) on delete cascade,
  tool_id     uuid not null references public.ai_tools(id) on delete cascade,

  proficiency integer not null default 1
                check (proficiency between 1 and 3),

  unique (student_id, tool_id)
);

comment on table public.ai_tool_proficiency is '1 = Foundational · 2 = Proficient · 3 = Advanced. Faculty-assessed at program end.';

create index proficiency_student_idx on public.ai_tool_proficiency(student_id);


-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- Public can READ published portfolios only.
-- Nobody can write from the frontend — staff use Supabase Studio.
-- ============================================================

alter table public.cohorts              enable row level security;
alter table public.students             enable row level security;
alter table public.assets               enable row level security;
alter table public.awards               enable row level security;
alter table public.notes                enable row level security;
alter table public.ai_tools             enable row level security;
alter table public.ai_tool_proficiency  enable row level security;

-- cohorts — anyone can read
create policy "Public can read cohorts"
  on public.cohorts for select
  to anon, authenticated
  using (true);

-- students — anyone can read PUBLISHED portfolios only
create policy "Public can read published students"
  on public.students for select
  to anon, authenticated
  using (is_published = true);

-- assets — readable if the student is published
create policy "Public can read assets of published students"
  on public.assets for select
  to anon, authenticated
  using (
    exists (
      select 1 from public.students s
      where s.id = assets.student_id
      and s.is_published = true
    )
  );

-- awards — readable if the student is published
create policy "Public can read awards of published students"
  on public.awards for select
  to anon, authenticated
  using (
    exists (
      select 1 from public.students s
      where s.id = awards.student_id
      and s.is_published = true
    )
  );

-- notes — readable if the student is published
create policy "Public can read notes of published students"
  on public.notes for select
  to anon, authenticated
  using (
    exists (
      select 1 from public.students s
      where s.id = notes.student_id
      and s.is_published = true
    )
  );

-- ai_tools — anyone can read (static, not sensitive)
create policy "Public can read ai_tools"
  on public.ai_tools for select
  to anon, authenticated
  using (true);

-- ai_tool_proficiency — readable if student is published
create policy "Public can read proficiency of published students"
  on public.ai_tool_proficiency for select
  to anon, authenticated
  using (
    exists (
      select 1 from public.students s
      where s.id = ai_tool_proficiency.student_id
      and s.is_published = true
    )
  );


-- ============================================================
-- HELPER VIEW: full_portfolio
-- Single query returns everything needed to render one portfolio.
-- Use this in your frontend: select * from full_portfolio where slug = 'priya-sharma-2026-c1'
-- ============================================================
create or replace view public.full_portfolio as
select
  s.id,
  s.slug,
  s.full_name,
  s.email,
  s.gender_pronoun,
  s.photo_url,
  s.product_name,
  s.product_description,
  s.product_photo_url,
  s.revenue,
  s.customers_reached,
  s.markets_attended,
  s.website_url,
  s.instagram_handle,
  s.flea_market_photos,
  s.demo_day_photos,
  s.certificate_url,
  s.is_published,
  s.created_at,

  -- cohort info
  c.year            as cohort_year,
  c.cohort_number,
  c.cohort_name,
  c.start_date      as cohort_start,
  c.end_date        as cohort_end,

  -- assets grouped by type as JSON arrays
  coalesce((
    select json_agg(a order by a.sort_order)
    from public.assets a
    where a.student_id = s.id and a.asset_type = 'influencer_video'
  ), '[]') as influencer_videos,

  coalesce((
    select json_agg(a order by a.sort_order)
    from public.assets a
    where a.student_id = s.id and a.asset_type = 'performance_video'
  ), '[]') as performance_videos,

  coalesce((
    select json_agg(a order by a.sort_order)
    from public.assets a
    where a.student_id = s.id and a.asset_type = 'static_ad'
  ), '[]') as static_ads,

  -- awards (null if none — frontend hides section)
  (
    select json_agg(aw order by aw.sort_order)
    from public.awards aw
    where aw.student_id = s.id
  ) as awards,

  -- notes (co-founder, mentor, peer)
  (
    select json_agg(n order by n.note_type)
    from public.notes n
    where n.student_id = s.id
  ) as notes,

  -- ai tools with proficiency for this student
  (
    select json_agg(
      json_build_object(
        'tool_name',   t.tool_name,
        'tool_use',    t.tool_use,
        'logo_url',    t.logo_url,
        'sort_order',  t.sort_order,
        'proficiency', p.proficiency
      )
      order by t.sort_order
    )
    from public.ai_tools t
    join public.ai_tool_proficiency p
      on p.tool_id = t.id and p.student_id = s.id
    where t.cohort_id = s.cohort_id
  ) as ai_tools

from public.students s
join public.cohorts c on c.id = s.cohort_id
where s.is_published = true;

comment on view public.full_portfolio is
  'Single query to render a complete portfolio. Filter by slug. e.g. select * from full_portfolio where slug = ''priya-sharma-2026-c1''';


-- ============================================================
-- SEED DATA — FFP 2026 Cohort 1 example
-- Delete or modify before going live
-- ============================================================

-- Insert cohort
insert into public.cohorts (year, cohort_number, cohort_name, start_date, end_date)
values (2026, 1, 'FFP Cohort 1 · 2026', '2026-06-01', '2026-06-14');

-- Insert AI tools for cohort 1 (static — same for all students)
-- Replace logo_url values with your actual Google Drive URLs
insert into public.ai_tools (cohort_id, tool_name, tool_use, logo_url, sort_order)
select
  c.id,
  tool_name,
  tool_use,
  logo_url,
  sort_order
from public.cohorts c,
(values
  ('ChatGPT',     'Business planning, product descriptions, customer research', 'REPLACE_WITH_DRIVE_URL', 1),
  ('Canva AI',    'Brand assets, ad creatives, social media content',           'REPLACE_WITH_DRIVE_URL', 2),
  ('Meta Ads AI', 'Performance marketing, audience targeting, ad copy',         'REPLACE_WITH_DRIVE_URL', 3),
  ('Gemini',      'Market research, competitor analysis, pricing strategy',     'REPLACE_WITH_DRIVE_URL', 4),
  ('ElevenLabs',  'AI voiceovers for product videos and reels',                 'REPLACE_WITH_DRIVE_URL', 5),
  ('Runway ML',   'AI video editing for influencer collab content',             'REPLACE_WITH_DRIVE_URL', 6)
) as tools(tool_name, tool_use, logo_url, sort_order)
where c.year = 2026 and c.cohort_number = 1;


-- ============================================================
-- HOW TO CONNECT TO YOUR PROJECT
-- 
-- 1. Go to Supabase → your project → SQL Editor
-- 2. Paste this entire file and click Run
-- 3. Go to Project Settings → API
-- 4. Copy: Project URL + anon public key
-- 5. In your frontend (HTML or Next.js):
--
--    const SUPABASE_URL = 'https://YOUR_PROJECT.supabase.co'
--    const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY'
--
-- 6. To fetch a portfolio by slug:
--    const { data } = await supabase
--      .from('full_portfolio')
--      .select('*')
--      .eq('slug', 'priya-sharma-2026-c1')
--      .single()
--
-- 7. To convert a Google Drive share URL to direct URL:
--    function driveUrl(shareUrl) {
--      const match = shareUrl.match(/\/d\/([a-zA-Z0-9_-]+)/)
--      if (!match) return shareUrl
--      return `https://drive.google.com/uc?export=view&id=${match[1]}`
--    }
-- ============================================================
