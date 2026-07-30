--  Web.Rate_Limit — a bounded, task-safe per-client HTTP request limiter. The
--  server accounts every request against a fixed-window counter keyed by client
--  IP; when a client exceeds Max_Requests within the window it is refused with
--  429 Too Many Requests until the window resets.
--
--  Time is passed in (Now, in seconds) so the algorithm is deterministic and
--  unit-testable; the server supplies a wall clock. The table is a fixed-size
--  hash table with bounded probing and oldest-entry eviction, so memory is
--  bounded no matter how many distinct clients appear.
package Web.Rate_Limit is

   --  A time value in whole seconds on any monotonic epoch the caller chooses.
   type Timestamp is range 0 .. 2 ** 63 - 1;

   --  Configure the limit. Max_Requests = 0 (the default) disables limiting and
   --  clears the table. A change resets all counters.
   procedure Configure (Max_Requests : Natural; Window_Seconds : Positive);

   --  Account for one request from Client at time Now. Allowed is False when the
   --  client has already made Max_Requests within the current window; Retry_After
   --  is then the seconds until that window resets (0 when Allowed).
   procedure Check
     (Client      : String;
      Now         : Timestamp;
      Allowed     : out Boolean;
      Retry_After : out Natural);

end Web.Rate_Limit;
