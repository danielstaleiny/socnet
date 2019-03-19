-- Actually gets friends + friends of friends which the user can see(not blocked)
create or replace function friends_of_friends(user_id int) returns setof int as $$
with friends as (
  select
    case when source_user_id = $1
      then target_user_id
      else source_user_id
    end as user_id
  from friendships
  where
    $1 in (source_user_id, target_user_id) and
    status = 'accepted')
select
  case
    when f0.source_user_id = $1
      then f0.target_user_id
    when f0.target_user_id = $1
      then f0.source_user_id
    when f0.source_user_id = f1.user_id
      then f0.target_user_id
    else f0.source_user_id
  end as user_id
from friendships f0
join friends f1 on
  f0.source_user_id = f1.user_id  or
  f0.target_user_id = f1.user_id
where
  f0.status = 'accepted'

except

select
  case when source_user_id = $1
    then target_user_id
    else source_user_id
  end as user_id
from friendships
where
  $1 in (source_user_id, target_user_id) and
  status = 'blocked';
$$ language sql security definer;