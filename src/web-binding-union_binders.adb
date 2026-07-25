package body Web.Binding.Union_Binders is

   use Web.Binding.Errors;
   use Wire_Strings;

   function Empty_Selector return Selector is
      S : Selector;
   begin
      return S;
   end Empty_Selector;

   function Map
     (S : Selector; Wire : String; Alt : Alternative) return Selector
   is
      Result : Selector := S;
   begin
      if Result.Count < Max_Alternatives then
         Result.Count := Result.Count + 1;
         Result.Entries (Result.Count) :=
           (Wire => To_Bounded_String (Wire, Drop => Ada.Strings.Right),
            Alt  => Alt);
      end if;
      return Result;
   end Map;

   function Resolve (S : Selector; Wire : String) return Selection is
   begin
      for I in 1 .. S.Count loop
         if To_String (S.Entries (I).Wire) = Wire then
            return (Found => True, Alt => S.Entries (I).Alt);
         end if;
      end loop;
      return (Found => False);
   end Resolve;

   function Missing_Error return Web.Binding.Errors.Error_Id is
     (Union_Missing_Discriminator);

   function Invalid_Error return Web.Binding.Errors.Error_Id is
     (Union_Invalid_Discriminator);

   function Resolve_Structural
     (Matches : Match_Array; Chosen : out Alternative) return Structural_Outcome
   is
      Count : Natural := 0;
   begin
      Chosen := Alternative'First;
      for A in Alternative loop
         if Matches (A) then
            Count := Count + 1;
            Chosen := A;
         end if;
      end loop;
      if Count = 1 then
         return Exactly_One;
      elsif Count = 0 then
         return No_Match;
      else
         return Ambiguous;
      end if;
   end Resolve_Structural;

   function Ambiguous_Error return Web.Binding.Errors.Error_Id is
     (Union_Ambiguous_Alternative);

   function No_Match_Error return Web.Binding.Errors.Error_Id is
     (Union_No_Matching_Alternative);

end Web.Binding.Union_Binders;
