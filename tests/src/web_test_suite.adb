with Web_Core_Tests;
with Web_E2E_Tests;
with Web_Live_Tests;
with Web_Protocol_Tests;
with Web_Runtime_Tests;
with Web_Transport_Tests;

package body Web_Test_Suite is
   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
   begin
      Web_Core_Tests.Add_Tests (Result);
      Web_Protocol_Tests.Add_Tests (Result);
      Web_Transport_Tests.Add_Tests (Result);
      Web_Live_Tests.Add_Tests (Result);
      Web_Runtime_Tests.Add_Tests (Result);
      Web_E2E_Tests.Add_Tests (Result);
      return Result;
   end Suite;
end Web_Test_Suite;
