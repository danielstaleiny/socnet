drop schema if exists core cascade;
create schema core;

set search_path = core, public;

create table users (
  id        serial  primary key
, username  text    not null     unique
);

create type audience as enum (
  'personal'
, 'friends_whitelist'
, 'friends_blacklist'
, 'friends'
, 'friends_of_friends'
, 'public'
);

create table users_details (
  user_id   int       primary key  references users(id)
, email     citext                 check ( email ~* '^.+@.+\..+$' )
, phone     text                   check ( phone ~* '^\d{3}-\d{3}-\d{4}$')
, audience  audience  not null     default 'friends'
);

create type friendship_status as enum (
  'pending'
, 'accepted'
, 'blocked'
);

create table friendships (
  source_user_id  int                not null references users(id)
, target_user_id  int                not null references users(id)
, status          friendship_status  not null
, blockee_id      int                null     references users(id)
, since           date               not null default now()

, primary key (source_user_id, target_user_id)
-- you can't send a friend request to yourself
, check       (source_user_id <> target_user_id)
-- don't let a block happen when a blockee_id is null or the blockee_id doesn't belong to the friendship
, check       (not (status = 'blocked' and (blockee_id is null or blockee_id not in (source_user_id, target_user_id))))
);

-- Allowed friendship status transition(all allowed except going back to pending)
--
-- pending->accepted<->blocked
--     |                  |
--     --------->----------
create or replace function check_friendship_status() returns trigger as $$
begin
  if old.status in ('accepted', 'blocked') and
     new.status = 'pending' then
    raise exception 'status cannot go back to pending';
  end if;
  -- remove blockee_id when unblocking
  if old.status = ('blocked') and
     new.status = 'accepted' then
    new.blockee_id = null;
  end if;
  return new;
end; $$ language plpgsql;
create trigger check_friendship_status before update on friendships
for each row execute procedure check_friendship_status();

-- unique combination, once a friend request is made the target user cannot create a friend request back to the source user
create unique index unique_friend_request_idx
on friendships(
  least(source_user_id, target_user_id)
, greatest(source_user_id, target_user_id)
);

-- for searches of the form: id in (source_user_id, target_user_id)
create index target_user_id_idx on friendships(target_user_id);

-- there'd be a lot of blocked_id nulls so use a partial index
create index blockee_id_idx on friendships(blockee_id) where blockee_id is not null;

create type access_type as enum (
  'whitelist'
, 'blacklist'
);

create table users_details_access (
  user_details_id   int          not null  references users_details(user_id)  on delete cascade
, source_user_id    int          not null
, target_user_id    int          not null
, access_type       access_type  not null

, primary key            (user_details_id, source_user_id, target_user_id, access_type)
, foreign key            (source_user_id, target_user_id)
  references friendships (source_user_id, target_user_id)
  on delete cascade
);

create table posts (
  id            serial    primary key
, creator_id    int       not null     references users(id)
, title         text      not null
, body          text      not null
, publish_date  date      not null     default now()
, audience      audience  not null     default 'friends'
);
-- posts would be searched by date or creator
create index post_publish_date_idx on posts(publish_date);
create index post_creator_id_idx on posts(creator_id);

create table posts_access (
  post_id         int          not null  references posts(id)  on delete cascade
, creator_id      int          not null  references users(id)
, source_user_id  int          not null
, target_user_id  int          not null
, access_type     access_type  not null

, primary key            (post_id, source_user_id, target_user_id, access_type)
, foreign key            (source_user_id, target_user_id)
  references friendships (source_user_id, target_user_id)
  on delete cascade
);

create table comments (
  id            serial    primary key
, post_id       int       not null     references posts(id)  on delete cascade
, user_id       int       not null     references users(id)
, body          text      not null
, comment_date  date      not null     default now()
);
