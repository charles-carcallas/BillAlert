begin;
-- The checked security-definer function remains the sole client entry point.
-- Its owner can still call this helper; older clients cannot guess an action
-- from a changed settlement state or bypass the version/retry checks.
do $$ begin
 if to_regprocedure('public.fn_correct_settlement_checked(uuid,text,text,timestamptz,uuid)') is null then
  raise exception 'Apply settlement_correction_recovery before this migration';
 end if;
end $$;
revoke all on function public.fn_correct_settlement(uuid,text) from public,anon,authenticated;
commit;
