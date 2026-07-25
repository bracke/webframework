package body Web.Binding.Results is

   function Succeeded (Item : Result) return Boolean is
   begin
      return Item.State = Success;
   end Succeeded;

   function Make_Success (Value : Value_Type) return Result is
   begin
      return (State => Success, Value => Value);
   end Make_Success;

   function Make_Failure
     (Errors : Web.Binding.Errors.Error_Collection) return Result is
   begin
      return (State => Failure, Errors => Errors);
   end Make_Failure;

   function Value_Of (Item : Result) return Value_Type is
   begin
      return Item.Value;
   end Value_Of;

   function Errors_Of
     (Item : Result) return Web.Binding.Errors.Error_Collection is
   begin
      return Item.Errors;
   end Errors_Of;

end Web.Binding.Results;
