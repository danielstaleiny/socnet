begin;

select no_plan();

set search_path = core, public;

\echo =======================
\echo friendships constraints
\echo =======================

set local role postgres;

select
  throws_ok(
    $$
    insert into friendships(source_user_id, target_user_id, status) values (1, 1, 'pending');
    $$,
    'new row for relation "friendships" violates check constraint "friendships_check"',
    'An user cannot send a friend request to himself'
  );

select
  throws_ok(
    $$
    insert into friendships(source_user_id, target_user_id, status) values (1, 5, 'pending');
    insert into friendships(source_user_id, target_user_id, status) values (5, 1, 'pending');
    $$,
    'duplicate key value violates unique constraint "unique_friend_request_idx"',
    'There can only be a friendship between two users'
  );

select
  throws_ok(
    $$
    insert into friendships(source_user_id, target_user_id, status) values (1, 5, 'pending');
    insert into friendships(source_user_id, target_user_id, status) values (5, 1, 'pending');
    $$,
    'duplicate key value violates unique constraint "unique_friend_request_idx"',
    'There can only be a friendship between two users'
  );

select
  throws_ok(
    $$
    insert into friendships(source_user_id, target_user_id, status, blockee_id) values (5, 6, 'blocked', null);
    $$,
    'new row for relation "friendships" violates check constraint "friendships_check1"',
    'Cannot block without adding a blockee_id'
  );

select
  throws_ok(
    $$
    insert into friendships(source_user_id, target_user_id, status, blockee_id) values (5, 6, 'blocked', 1);
    $$,
    'new row for relation "friendships" violates check constraint "friendships_check1"',
    'blockee_id can only be one of the users in the friendship'
  );

select
  throws_ok(
    $$
    update friendships set status = 'pending' where source_user_id = 1 and target_user_id = 2;
    $$,
    'P0001',
    'status cannot go back to pending',
    'accepted status cannot go back to pending'
  );

select
  throws_ok(
    $$
    update friendships set status = 'pending' where source_user_id = 6 and target_user_id = 5;
    $$,
    'P0001',
    'status cannot go back to pending',
    'blocked status cannot go back to pending'
  );

\echo ===============
\echo friendships rls
\echo ===============

set local role socnet_anon;
reset "request.jwt.claim.user_id";

select
  throws_ok(
    $$
    select * from friendships;
    $$,
    42501,
    'permission denied for relation friendships',
    'public cannot see any friendships'
  );

set local role socnet_user;
set local "request.jwt.claim.user_id" to 1;

select
  throws_ok(
    $$
    insert into friendships(source_user_id, target_user_id, status) values (3, 6, 'pending');
    $$,
    42501,
    'new row violates row-level security policy for table "friendships"',
    'an user cannot create friendships for other users'
  );

select
  lives_ok(
    $$
    insert into friendships(source_user_id, target_user_id, status) values (1, 6, 'pending');
    $$,
    'an user can create friendships when he is part of that friendship'
  );

\echo
\echo Blocked friendships
\echo ===================
\echo

set local role socnet_user;
set local "request.jwt.claim.user_id" to 5;

select
  is_empty(
    $$
    select * from friendships where source_user_id in (3, 6) and target_user_id = 5
    $$,
    'the blockee cannot see blocked friendships'
  );

select
  is_empty(
    $$
    update friendships set status = 'accepted' where status = 'blocked' returning *
    $$,
    'the blockee cannot modify blocked friendships'
  );

select
  is_empty(
    $$
    delete from friendships where source_user_id in (6,3) and target_user_id = 5 returning *;
    $$,
    'the blockee cannot delete blocked friendships'
  );

set local role socnet_user;
set local "request.jwt.claim.user_id" to 6;

select
  results_eq(
    $$
    update friendships
    set status = 'accepted', blockee_id = null
    where
      6 in (source_user_id, target_user_id) and
      status = 'blocked' and blockee_id = 5
    returning 1
    $$,
    $$
    values(1)
    $$,
    'the blocker can update blocked status'
  );

select * from finish();

do $$ begin assert num_failed() = 0; end $$;

rollback;
