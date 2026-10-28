-- Run manually in Supabase SQL Editor. Changes the bill-ready message template.
-- Applies to future posting events; does not resend or rewrite queued messages.
-- The existing renderer also uses this text for the bill-ready in-app alert.
-- Meter Reader bills covered by BOHECO retain their separate coverage message.
begin;
do $$ begin
  if (select count(*) from public.settings where id=1)<>1 then
    raise exception 'Expected settings row 1';
  end if;
end $$;
update public.settings
set sms_template = 'BillAlert: {name}, {month}. Previous reading: {previous_reading} kWh. Present reading: {current_reading} kWh. Consumed: {usage} kWh. Amount: PHP {amount}. Due: {due_date}. Account: {account_no}.'
where id=1;
select sms_template from public.settings where id=1;
commit;
