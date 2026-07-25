with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Web.Binding.Errors;
with Web.Binding.Percent;

package body Web.Binding.Query is

   function Parse (Query_String : String) return Query_Source is
      Result : Query_Source;
      First  : Integer := Query_String'First;

      --  Add one "name=value" token (either part optional).
      procedure Add_Token (Token_First, Token_Last : Integer) is
      begin
         if Token_First > Token_Last then
            return;  --  empty token (e.g. "&&")
         end if;
         if Result.Length >= Max_Pairs then
            Result.Overflow := True;
            return;
         end if;

         declare
            Eq        : Integer := 0;
            Name_Ok   : Boolean;
            Value_Ok  : Boolean := True;
         begin
            for I in Token_First .. Token_Last loop
               if Query_String (I) = '=' then
                  Eq := I;
                  exit;
               end if;
            end loop;

            Result.Length := Result.Length + 1;
            declare
               P : Query_Pair renames Result.Pairs (Result.Length);
            begin
               P.Ordinal := Result.Length;
               if Eq = 0 then
                  P.Name := To_Unbounded_String
                    (Percent.Decode
                       (Query_String (Token_First .. Token_Last), True, Name_Ok));
                  P.Value := Null_Unbounded_String;
               else
                  P.Name := To_Unbounded_String
                    (Percent.Decode
                       (Query_String (Token_First .. Eq - 1), True, Name_Ok));
                  P.Value := To_Unbounded_String
                    (Percent.Decode
                       (Query_String (Eq + 1 .. Token_Last), True, Value_Ok));
               end if;
               P.Bad := not (Name_Ok and then Value_Ok);
            end;
         end;
      end Add_Token;

   begin
      if Query_String'Length = 0 then
         return Result;
      end if;
      for I in Query_String'Range loop
         if Query_String (I) = '&' then
            Add_Token (First, I - 1);
            First := I + 1;
         end if;
      end loop;
      Add_Token (First, Query_String'Last);
      return Result;
   end Parse;

   function Lookup
     (Source : Query_Source; Name : String)
      return Web.Binding.Sources.Occurrences
   is
      Result : Web.Binding.Sources.Occurrences := Web.Binding.Sources.Empty;
   begin
      for I in 1 .. Source.Length loop
         if To_String (Source.Pairs (I).Name) = Name then
            declare
               Loc : Web.Binding.Errors.Source_Location;
            begin
               Loc.Has_Ordinal := True;
               Loc.Ordinal := Parameter_Ordinal (Source.Pairs (I).Ordinal);
               Web.Binding.Sources.Add
                 (Result,
                  To_String (Source.Pairs (I).Value),
                  Loc,
                  Source.Pairs (I).Bad);
            end;
         end if;
      end loop;
      return Result;
   end Lookup;

   function Pair_Count (Source : Query_Source) return Natural is
   begin
      return Source.Length;
   end Pair_Count;

   function Truncated (Source : Query_Source) return Boolean is
   begin
      return Source.Overflow;
   end Truncated;

end Web.Binding.Query;
