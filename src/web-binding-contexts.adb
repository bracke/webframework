package body Web.Binding.Contexts is

   function New_Context
     (Limits      : Web.Binding.Limits.Binding_Limits :=
        Web.Binding.Limits.Default_Limits;
      Mode        : Web.Binding.Policies.Aggregation_Mode :=
        Web.Binding.Policies.Aggregate_Fields;
      Diagnostics : Boolean := False;
      Correlation : String := "") return Binding_Context is
   begin
      return
        (Limits      => Limits,
         Mode        => Mode,
         Diagnostics => Diagnostics,
         Correlation => Correlation_Strings.To_Bounded_String
           (Correlation, Drop => Ada.Strings.Right));
   end New_Context;

end Web.Binding.Contexts;
