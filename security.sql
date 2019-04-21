drop role if exists socnet_user;
create role socnet_user;

drop role if exists socnet_anon;
create role socnet_anon;

grant usage on schema core to socnet_user, socnet_anon;

alter table  users                 enable row level security;
alter table  users_details         enable row level security;
alter table  users_details_access  enable row level security;
alter table  friendships           enable row level security;
alter table  posts_access          enable row level security;
alter table  posts                 enable row level security;
alter table  comments              enable row level security;

---------
--users--
---------
grant select, update(username) on users to socnet_user;

drop policy if exists users_policy on users;
create policy users_policy on users to socnet_user
using(
  util.jwt_user_id() = users.id  -- user can always see its profile
  or
  users.id not in (
    select util.blocker_ids(util.jwt_user_id())
  )
)
with check(
  util.jwt_user_id() = users.id
);

-----------------
--users_details--
-----------------
grant select, insert, update(email, phone, audience) on users_details to socnet_user;
grant select on users_details to socnet_anon;

drop policy if exists users_details_policy on users_details;
create policy users_details_policy on users_details to socnet_user
using(
  util.jwt_user_id() = users_details.user_id -- user can always see its details
  or
  case audience
    when 'public' -- all users can see the user details except the blocked ones
      then users_details.user_id not in (
        select util.blocker_ids(util.jwt_user_id())
      )
    when 'personal'
      then util.jwt_user_id() = users_details.user_id
    when 'friends'
      then util.jwt_user_id() in (
        select
          case when f.source_user_id = util.jwt_user_id()
            then f.target_user_id
            else f.source_user_id
          end
        from friendships f
        where
          status = 'accepted'
      )
    when 'friends_of_friends'
      then util.jwt_user_id() in (
        select util.friends_of_friends(users_details.user_id)
      )
    when 'friends_whitelist'
      then util.jwt_user_id() in (
        select
          case when acc.source_user_id = users_details.user_id
            then acc.target_user_id
            else acc.source_user_id
          end
        from users_details_access acc
        where
          acc.users_details_id = users_details.user_id  and
          acc.access_type      = 'whitelist'
      )
    when 'friends_blacklist'
      then util.jwt_user_id() in (
        select
          case when f.source_user_id = users_details.user_id
            then f.target_user_id
            else f.source_user_id
          end
        from friendships f
        where
          status = 'accepted'

        except

        select
          case when acc.source_user_id = users_details.user_id
            then acc.target_user_id
            else acc.source_user_id
          end
        from users_details_access acc
        where
          acc.users_details_id = users_details.user_id  and
          acc.access_type      = 'blacklist'
      )
  end
)
with check(
  util.jwt_user_id() = users_details.user_id
);

drop policy if exists users_details_policy_anon on users_details;
create policy users_details_policy_anon on users_details to socnet_anon
using (
  users_details.audience = 'public'
)
with check (false);

------------------------
--users_details_access--
------------------------
grant select, insert, delete on users_details_access to socnet_user;

drop policy if exists users_details_access_policy on users_details_access;
create policy users_details_access_policy on users_details_access to socnet_user
using( -- can see accesess to users_details_access the user owns and the ones he's been assigned with
  util.jwt_user_id() in (source_user_id, target_user_id)
)
with check( -- can only insert when the users_details_access belongs to the user
  util.jwt_user_id() = users_details_access.users_details_id
);

drop policy if exists users_details_access_delete_policy on users_details_access;
create policy users_details_access_delete_policy
on users_details_access as restrictive for delete to socnet_user
using(
  util.jwt_user_id() = users_details_access.users_details_id
);

---------------
--friendships--
---------------
grant select, insert, update(status, since, blockee_id), delete on friendships to socnet_user;

drop policy if exists friendships_policy on friendships;
create policy friendships_policy on friendships to socnet_user
-- can see all friendships except the blocked ones
using(
  case status
    when 'blocked'
      then blockee_id is null or util.jwt_user_id() <> blockee_id
    else true
  end
)
with check(
  util.jwt_user_id() in (source_user_id, target_user_id)
);

drop policy if exists delete_policy on friendships;
create policy delete_policy on friendships
as restrictive for delete to socnet_user
using(
  util.jwt_user_id() in (source_user_id, target_user_id)
);

----------------
--posts_access--
----------------
grant select, insert, delete on posts_access to socnet_user;

drop policy if exists posts_access_policy on posts_access;
create policy posts_access_policy on posts_access to socnet_user
using( -- can see post accesess to posts the user owns and the ones he's been assigned with
  util.jwt_user_id() in (source_user_id, target_user_id)
)
with check( -- can only insert when the post_id belongs to the user
  util.jwt_user_id() = posts_access.creator_id
);

drop policy if exists delete_policy on posts_access;
create policy delete_policy on posts_access
as restrictive for delete to socnet_user
using(
  util.jwt_user_id() = posts_access.creator_id
);

---------
--posts--
---------
grant select, insert, update(title, body, audience), delete on posts to socnet_user;
grant usage on sequence posts_id_seq to socnet_user;
grant select on posts to socnet_anon; -- for the case of public posts

drop policy if exists posts_users_policy on posts;
create policy posts_users_policy on posts to socnet_user
using (
  util.jwt_user_id() = posts.creator_id -- creator can always see its post
  or
  case audience
    when 'public' -- all users can see the posts except the blocked ones
      then posts.creator_id not in (
        select util.blocker_ids(util.jwt_user_id())
      )
    when 'personal'
      then util.jwt_user_id() = posts.creator_id
    when 'friends'
      then util.jwt_user_id() in (
        select
          case when f.source_user_id = posts.creator_id
            then f.target_user_id
            else f.source_user_id
          end
        from friendships f
        where
          status = 'accepted'
      )
    when 'friends_of_friends'
      then util.jwt_user_id() in (
        select util.friends_of_friends(posts.creator_id)
      )
    when 'friends_whitelist'
      then util.jwt_user_id() in (
        select
          case when acc.source_user_id = posts.creator_id
            then acc.target_user_id
            else acc.source_user_id
          end
        from posts_access acc
        where
          acc.post_id     = posts.id    and
          acc.access_type = 'whitelist'
      )
    when 'friends_blacklist'
      then util.jwt_user_id() in (
        select
          case when f.source_user_id = posts.creator_id
            then f.target_user_id
            else f.source_user_id
          end
        from friendships f
        where
          status = 'accepted'

        except

        select
          case when acc.source_user_id = posts.creator_id
            then acc.target_user_id
            else acc.source_user_id
          end
        from posts_access acc
        where
          acc.post_id     = posts.id    and
          acc.access_type = 'blacklist'
      )
  end
)
with check (
  util.jwt_user_id() = posts.creator_id
);

drop policy if exists delete_policy on posts;
create policy delete_policy on posts
as restrictive for delete to socnet_user
using(
  util.jwt_user_id() = posts.creator_id
);

drop policy if exists posts_anons_policy on posts;
create policy posts_anons_policy on posts to socnet_anon
using (
  posts.audience = 'public'
)
with check (false);

------------
--comments--
------------

grant select on comments to socnet_anon; -- for the case of public posts
grant usage on sequence comments_id_seq to socnet_user;
grant all on comments to socnet_user;

drop policy if exists anon_comments_policy on comments;
create policy anon_comments_policy on comments for select to socnet_anon
using (
  exists (
    select 1
    from posts
    where posts.id = comments.post_id)
);

drop policy if exists socnet_user_policy on comments;
create policy socnet_user_policy on comments to socnet_user
using (
  exists (
    select 1
    from posts
    where posts.id = comments.post_id)
  and
  comments.user_id not in (
    select util.blocker_ids(util.jwt_user_id())
  )
)
with check (
  util.jwt_user_id() = comments.user_id
);

drop policy if exists socnet_user_delete_policy on comments;
create policy socnet_user_delete_policy on comments
as restrictive for delete to socnet_user
using (
  util.jwt_user_id() = comments.user_id
);
