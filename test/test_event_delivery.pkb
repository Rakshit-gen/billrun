create or replace package body test_event_delivery as

  -- Dequeues until an event of p_type turns up or the queue is empty,
  -- committing each dequeue. True if one was found.
  function drain_until(p_type varchar2) return boolean is
    l_event billing_event_t;
  begin
    for i in 1 .. 1000 loop
      l_event := billing_events.next_event(p_wait => 1);
      commit;
      if l_event is null then
        return false;
      elsif l_event.event_type = p_type then
        return true;
      end if;
    end loop;
    return false;
  end drain_until;

  procedure committed_is_delivered is
  begin
    billing_events.publish('TEST_COMMITTED', -1, p_payload => '{}');
    commit;
    ut.expect(drain_until('TEST_COMMITTED')).to_be_true();
  end committed_is_delivered;

  procedure rolled_back_is_not is
  begin
    billing_events.publish('TEST_ROLLED_BACK', -1, p_payload => '{}');
    rollback;
    ut.expect(drain_until('TEST_ROLLED_BACK')).to_be_false();
  end rolled_back_is_not;

end test_event_delivery;
/
