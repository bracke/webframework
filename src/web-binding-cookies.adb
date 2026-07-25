package body Web.Binding.Cookies is

   function Lookup
     (Jar : Web.Cookie.Cookie_Jar; Name : String)
      return Web.Binding.Sources.Occurrences
   is
      Result : Web.Binding.Sources.Occurrences := Web.Binding.Sources.Empty;
   begin
      if Web.Cookie.Has (Jar, Name) then
         declare
            Value      : constant String := Web.Cookie.Value (Jar, Name);
            Duplicates : constant Natural :=
              Natural'Max (1, Web.Cookie.Count (Jar, Name));
         begin
            for I in 1 .. Duplicates loop
               Web.Binding.Sources.Add (Result, Value);
            end loop;
         end;
      end if;
      return Result;
   end Lookup;

end Web.Binding.Cookies;
