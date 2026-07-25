with Ada.Strings.Bounded;
with Web.Binding.Limits;
with Web.Binding.Policies;

--  Per-request binding context.
--
--  A small bundle of the request-scoped knobs a binder needs: the effective
--  limits, the aggregation mode, whether diagnostics are on, and a redacted
--  correlation id for structured diagnostics. It carries no application-global
--  mutable state; sources, the body stream and an upload session are held
--  alongside it by the handler, not inside it.
package Web.Binding.Contexts is

   Max_Correlation : constant := 64;

   package Correlation_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Correlation);

   type Binding_Context is record
      Limits      : Web.Binding.Limits.Binding_Limits;
      Mode        : Web.Binding.Policies.Aggregation_Mode :=
        Web.Binding.Policies.Aggregate_Fields;
      Diagnostics : Boolean := False;
      Correlation : Correlation_Strings.Bounded_String;
   end record;

   --  Create a per-request context.
   --  @param Limits The effective limits.
   --  @param Mode The aggregation mode.
   --  @param Diagnostics Whether diagnostics are enabled.
   --  @param Correlation A request correlation id.
   --  @return The context.
   function New_Context
     (Limits      : Web.Binding.Limits.Binding_Limits :=
        Web.Binding.Limits.Default_Limits;
      Mode        : Web.Binding.Policies.Aggregation_Mode :=
        Web.Binding.Policies.Aggregate_Fields;
      Diagnostics : Boolean := False;
      Correlation : String := "") return Binding_Context;

end Web.Binding.Contexts;
