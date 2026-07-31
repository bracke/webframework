--  App.Health -- register the example app's liveness and readiness probes with
--  the process-wide Health_Runtime.Checker, so /healthz and /readyz report real
--  dependency health rather than a static 200.
package App.Health is

   --  Register the probes. Call once at startup.
   procedure Setup;

end App.Health;
