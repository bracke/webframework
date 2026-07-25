with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Web.Binding.Route is

   function Empty return Route_Captures is
      Result : Route_Captures;
   begin
      return Result;
   end Empty;

   function Add
     (Captures : Route_Captures;
      Name     : String;
      Value    : String) return Route_Captures
   is
      Result : Route_Captures := Captures;
   begin
      if Result.Length < Max_Captures then
         Result.Length := Result.Length + 1;
         Result.Items (Result.Length) :=
           (Name  => To_Unbounded_String (Name),
            Value => To_Unbounded_String (Value));
      end if;
      return Result;
   end Add;

   function Lookup
     (Captures : Route_Captures; Name : String)
      return Web.Binding.Sources.Occurrences
   is
      Result : Web.Binding.Sources.Occurrences := Web.Binding.Sources.Empty;
   begin
      for I in 1 .. Captures.Length loop
         if To_String (Captures.Items (I).Name) = Name then
            Web.Binding.Sources.Add
              (Result, To_String (Captures.Items (I).Value));
         end if;
      end loop;
      return Result;
   end Lookup;

   function Count (Captures : Route_Captures) return Natural is
   begin
      return Captures.Length;
   end Count;

end Web.Binding.Route;
