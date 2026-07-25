package body Web.Binding.Sources is

   use Web.Binding.Policies;
   use Web.Binding.Errors;

   function Empty return Occurrences is
      Result : Occurrences;
   begin
      return Result;
   end Empty;

   procedure Add
     (Into      : in out Occurrences;
      Value     : String;
      Location  : Web.Binding.Errors.Source_Location :=
        Web.Binding.Errors.No_Location;
      Malformed : Boolean := False) is
   begin
      if Into.Length >= Max_Occurrences then
         Into.Overflow := True;
         return;
      end if;
      Into.Length := Into.Length + 1;
      Into.Items (Into.Length) :=
        (Text  => To_Unbounded_String (Value),
         Place => Location,
         Bad   => Malformed);
   end Add;

   function Count (Item : Occurrences) return Natural is
   begin
      return Item.Length;
   end Count;

   function Card (Item : Occurrences) return Cardinality is
   begin
      return (case Item.Length is
                 when 0      => Absent,
                 when 1      => Present_Once,
                 when others => Present_Multiple);
   end Card;

   function Value (Item : Occurrences; Index : Positive) return String is
   begin
      return To_String (Item.Items (Index).Text);
   end Value;

   function Location
     (Item : Occurrences; Index : Positive)
      return Web.Binding.Errors.Source_Location is
   begin
      return Item.Items (Index).Place;
   end Location;

   function Malformed (Item : Occurrences; Index : Positive) return Boolean is
   begin
      return Item.Items (Index).Bad;
   end Malformed;

   function Truncated (Item : Occurrences) return Boolean is
   begin
      return Item.Overflow;
   end Truncated;

   function Split (Text : String; Delimiter : Character) return Occurrences is
      Result : Occurrences;
      First  : Integer := Text'First;
      Ord    : Natural := 0;

      procedure Emit (Piece_First, Piece_Last : Integer) is
         Loc : Web.Binding.Errors.Source_Location;
      begin
         Ord := Ord + 1;
         Loc.Has_Ordinal := True;
         Loc.Ordinal := Parameter_Ordinal (Ord);
         Add (Result, Text (Piece_First .. Piece_Last), Loc);
      end Emit;

   begin
      if Text'Length = 0 then
         return Result;
      end if;
      for I in Text'Range loop
         if Text (I) = Delimiter then
            Emit (First, I - 1);
            First := I + 1;
         end if;
      end loop;
      Emit (First, Text'Last);
      return Result;
   end Split;

   --  Whether every retained occurrence has the same value text.
   function All_Identical (Item : Occurrences) return Boolean is
   begin
      for I in 2 .. Item.Length loop
         if Item.Items (I).Text /= Item.Items (1).Text then
            return False;
         end if;
      end loop;
      return True;
   end All_Identical;

   function Resolve_Scalar
     (Item       : Occurrences;
      Duplicates : Web.Binding.Policies.Duplicate_Policy;
      On_Empty   : Web.Binding.Policies.Empty_Policy) return Scalar_Resolution
   is
      Chosen : Positive := 1;
   begin
      if Item.Length = 0 then
         return (State => Resolved_Missing);
      end if;

      if Item.Length > 1 then
         case Duplicates is
            when Reject | Collect_All =>
               return (State => Resolved_Duplicate);
            when Use_First =>
               Chosen := 1;
            when Use_Last =>
               Chosen := Item.Length;
            when Require_Identical =>
               if All_Identical (Item) then
                  Chosen := 1;
               else
                  return (State => Resolved_Duplicate);
               end if;
         end case;
      end if;

      if Item.Items (Chosen).Bad then
         return (State => Resolved_Malformed, Index => Chosen);
      end if;

      if Length (Item.Items (Chosen).Text) = 0 then
         case On_Empty is
            when Allow_And_Decode | Map_To_Empty_Collection =>
               return (State => Resolved_Value, Index => Chosen);
            when Reject_Empty =>
               return (State => Resolved_Empty, Index => Chosen);
            when Treat_As_Missing | Map_To_None =>
               return (State => Resolved_Missing);
         end case;
      end if;

      return (State => Resolved_Value, Index => Chosen);
   end Resolve_Scalar;

   function Resolution_Error
     (State : Resolution_State) return Web.Binding.Errors.Error_Id is
   begin
      case State is
         when Resolved_Missing   => return Binding_Missing;
         when Resolved_Duplicate => return Binding_Duplicate;
         when Resolved_Empty     => return Binding_Empty_Not_Allowed;
         when Resolved_Malformed => return Form_Invalid_Percent_Escape;
         when Resolved_Value     => return Internal_Decoder_Failure;
      end case;
   end Resolution_Error;

end Web.Binding.Sources;
