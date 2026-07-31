with Ada.Directories;
with Ada.Strings.Fixed;
with Health;
with Health.Errors;
with Health_Runtime.Checker;
with App.Projects;

package body App.Health is

   package Chk renames Standard.Health_Runtime.Checker;

   function Trimmed (N : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));

   --  Liveness: the process answers, so it is alive. A liveness probe stays
   --  local -- it must never fail because a remote dependency is down.
   function Process_Probe return Chk.Outcome is
     (Chk.Result (Standard.Health.Healthy, "process up"));

   --  Readiness: the projects store is reachable. Run a real, cheap query; if it
   --  raises, report Unhealthy so the instance leaves rotation.
   function Database_Probe return Chk.Outcome is
   begin
      return Chk.Result
        (Standard.Health.Healthy,
         "projects store reachable ("
         & Trimmed (Natural (App.Projects.Get_Projects.Length)) & " rows)");
   exception
      when others =>
         return Chk.Result
           (Standard.Health.Unhealthy, "projects store query failed");
   end Database_Probe;

   --  Readiness, but informational: missing static assets degrade the report
   --  rather than take the instance out of rotation.
   function Static_Assets_Probe return Chk.Outcome is
   begin
      if Ada.Directories.Exists ("example_app/static") then
         return Chk.Result (Standard.Health.Healthy, "static assets present");
      else
         return Chk.Result
           (Standard.Health.Degraded, "static assets directory missing");
      end if;
   end Static_Assets_Probe;

   procedure Setup is
      Cat : Standard.Health.Errors.Error_Category;
   begin
      Chk.Register
        (Chk.Default.all, "process", Process_Probe'Access,
         Kind => Standard.Health.Liveness, Category => Cat);
      Chk.Register
        (Chk.Default.all, "database", Database_Probe'Access,
         Kind => Standard.Health.Readiness,
         Criticality => Standard.Health.Critical, Category => Cat);
      Chk.Register
        (Chk.Default.all, "static_assets", Static_Assets_Probe'Access,
         Kind => Standard.Health.Readiness,
         Criticality => Standard.Health.Informational, Category => Cat);
   end Setup;

end App.Health;
