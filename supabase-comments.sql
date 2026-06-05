create extension if not exists pgcrypto;

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.comments(id) on delete cascade,
  nickname text not null default '匿名网友',
  content text not null,
  likes_count integer not null default 0 check (likes_count >= 0),
  hidden boolean not null default false,
  created_at timestamptz not null default now(),
  constraint comments_content_not_blank check (length(trim(content)) > 0),
  constraint comments_nickname_not_blank check (length(trim(nickname)) > 0)
);

create table if not exists public.comment_likes (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid not null references public.comments(id) on delete cascade,
  client_id text not null,
  created_at timestamptz not null default now(),
  constraint comment_likes_client_not_blank check (length(trim(client_id)) > 0),
  constraint comment_likes_unique_client unique (comment_id, client_id)
);

create index if not exists comments_parent_id_idx on public.comments(parent_id);
create index if not exists comments_visible_time_idx on public.comments(hidden, created_at desc);
create index if not exists comments_rank_idx on public.comments(hidden, likes_count desc, created_at desc);
create index if not exists comment_likes_comment_id_idx on public.comment_likes(comment_id);

alter table public.comments enable row level security;
alter table public.comment_likes enable row level security;

drop policy if exists "public can read visible comments" on public.comments;
create policy "public can read visible comments"
on public.comments
for select
to anon
using (hidden = false);

drop policy if exists "anon can insert comments" on public.comments;
create policy "anon can insert comments"
on public.comments
for insert
to anon
with check (
  hidden = false
  and likes_count = 0
  and length(trim(nickname)) between 1 and 18
  and length(trim(content)) between 1 and 1000
);

drop policy if exists "public can read likes" on public.comment_likes;
create policy "public can read likes"
on public.comment_likes
for select
to anon
using (true);

drop policy if exists "anon can insert likes" on public.comment_likes;
create policy "anon can insert likes"
on public.comment_likes
for insert
to anon
with check (length(trim(client_id)) > 0);

create or replace function public.increment_comment_likes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.comments
  set likes_count = likes_count + 1
  where id = new.comment_id;

  return new;
end;
$$;

drop trigger if exists comment_likes_increment_count on public.comment_likes;
create trigger comment_likes_increment_count
after insert on public.comment_likes
for each row
execute function public.increment_comment_likes();
