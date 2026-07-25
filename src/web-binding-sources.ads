with Ada.Strings.Unbounded;
with Web.Binding.Errors;
with Web.Binding.Policies;

--  Source value model and scalar resolution.
--
--  A lookup against a request source yields an ordered, bounded list of
--  Occurrences -- every value supplied for a name, in request order, with its
--  source location and a malformed-encoding flag. Duplicates and order are
--  preserved (nothing is collapsed before a policy is applied), which is what
--  lets duplicate handling be explicit and deterministic (BIND-007).
--
--  Resolve_Scalar reduces the occurrences to a single decision given the
--  duplicate and empty policies. Missing, present-empty and present-value are
--  distinct outcomes.
package Web.Binding.Sources is

   type Cardinality is (Absent, Present_Once, Present_Multiple);

   --  The hard cap on retained occurrences of one name.
   Max_Occurrences : constant := 64;

   type Occurrences is private;

   --  An empty occurrence list.
   --  @return An empty list.
   function Empty return Occurrences;

   --  Append one occurrence in request order. Beyond the cap the value is
   --  dropped and the list is marked truncated.
   --  @param Into The list to extend.
   --  @param Value The raw (decoded) value text.
   --  @param Location The source location, if known.
   --  @param Malformed Whether this value had a source-encoding error.
   procedure Add
     (Into      : in out Occurrences;
      Value     : String;
      Location  : Web.Binding.Errors.Source_Location :=
        Web.Binding.Errors.No_Location;
      Malformed : Boolean := False);

   --  The number of retained occurrences.
   --  @param Item The list.
   --  @return The count.
   function Count (Item : Occurrences) return Natural;

   --  The cardinality of the list.
   --  @param Item The list.
   --  @return Absent, Present_Once or Present_Multiple.
   function Card (Item : Occurrences) return Cardinality;

   --  The value at a 1-based position.
   --  @param Item The list.
   --  @param Index The position (1 .. Count).
   --  @return The value text.
   function Value (Item : Occurrences; Index : Positive) return String;

   --  The source location at a position.
   --  @param Item The list.
   --  @param Index The position.
   --  @return The location.
   function Location
     (Item : Occurrences; Index : Positive)
      return Web.Binding.Errors.Source_Location;

   --  Whether the occurrence at a position had a source-encoding error.
   --  @param Item The list.
   --  @param Index The position.
   --  @return True when malformed.
   function Malformed (Item : Occurrences; Index : Positive) return Boolean;

   --  Whether occurrences were dropped past the cap.
   --  @param Item The list.
   --  @return True when truncated.
   function Truncated (Item : Occurrences) return Boolean;

   --  The outcome of resolving a scalar descriptor against occurrences.
   type Resolution_State is
     (Resolved_Value,
      Resolved_Missing,
      Resolved_Empty,
      Resolved_Duplicate,
      Resolved_Malformed);

   type Scalar_Resolution (State : Resolution_State := Resolved_Missing) is record
      case State is
         when Resolved_Value | Resolved_Empty | Resolved_Malformed =>
            Index : Positive;
         when others =>
            null;
      end case;
   end record;

   --  Reduce occurrences to a single scalar decision, deterministically.
   --  Reject rejects any duplicate; Use_First/Use_Last pick an end;
   --  Require_Identical accepts repeats only when all values are equal. Empty
   --  handling follows On_Empty. Missing (no occurrences) is Resolved_Missing.
   --  @param Item The occurrences.
   --  @param Duplicates The duplicate policy.
   --  @param On_Empty The empty-value policy.
   --  @return The resolution.
   function Resolve_Scalar
     (Item       : Occurrences;
      Duplicates : Web.Binding.Policies.Duplicate_Policy;
      On_Empty   : Web.Binding.Policies.Empty_Policy) return Scalar_Resolution;

   --  The binding error id a non-value resolution implies: Resolved_Missing ->
   --  binding.missing, Resolved_Duplicate -> binding.duplicate, Resolved_Empty
   --  -> binding.empty_not_allowed, Resolved_Malformed -> form.invalid_percent_
   --  escape.
   --  @param State The resolution state (not Resolved_Value).
   --  @return The corresponding error id.
   function Resolution_Error
     (State : Resolution_State) return Web.Binding.Errors.Error_Id
     with Pre => State /= Resolved_Value;

private

   use Ada.Strings.Unbounded;

   type Occurrence is record
      Text      : Unbounded_String;
      Place     : Web.Binding.Errors.Source_Location;
      Bad       : Boolean := False;
   end record;

   type Occurrence_Array is array (1 .. Max_Occurrences) of Occurrence;

   type Occurrences is record
      Length    : Natural := 0;
      Overflow  : Boolean := False;
      Items     : Occurrence_Array;
   end record;

end Web.Binding.Sources;
