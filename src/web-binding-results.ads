with Web.Binding.Errors;

--  A typed binding result: either a fully finalized value or a bounded error
--  collection, never both and never a partial value (invariant BIND-002). The
--  value component exists only in the Success variant, so a failed bind cannot
--  hand back a half-built record.
generic
   type Value_Type is private;
package Web.Binding.Results is

   type Outcome is (Success, Failure);

   type Result (State : Outcome := Failure) is record
      case State is
         when Success =>
            Value : Value_Type;
         when Failure =>
            Errors : Web.Binding.Errors.Error_Collection;
      end case;
   end record;

   --  Whether the result holds a value.
   --  @param Item The result.
   --  @return True when successful.
   function Succeeded (Item : Result) return Boolean;

   --  A successful result wrapping a finalized value.
   --  @param Value The finalized target value.
   --  @return A success result.
   function Make_Success (Value : Value_Type) return Result;

   --  A failed result carrying the accumulated errors.
   --  @param Errors The bounded error collection.
   --  @return A failure result.
   function Make_Failure
     (Errors : Web.Binding.Errors.Error_Collection) return Result;

   --  The finalized value of a successful result.
   --  @param Item The result (must be successful).
   --  @return The value.
   function Value_Of (Item : Result) return Value_Type
     with Pre => Succeeded (Item);

   --  The error collection of a failed result.
   --  @param Item The result (must be a failure).
   --  @return The errors.
   function Errors_Of
     (Item : Result) return Web.Binding.Errors.Error_Collection
     with Pre => not Succeeded (Item);

end Web.Binding.Results;
