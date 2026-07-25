with Web_Binding_Tests;
with Web_Binding_Decoder_Tests;
with Web_Binding_Decoder_Ext_Tests;
with Web_Binding_Source_Tests;
with Web_Binding_Record_Tests;
with Web_Binding_Collection_Tests;
with Web_Binding_URLEncoded_Tests;
with Web_Binding_JSON_Tests;
with Web_Binding_JSON_Bind_Tests;
with Web_Binding_Union_Tests;
with Web_Binding_Media_Tests;
with Web_Binding_Multipart_Tests;
with Web_Binding_Upload_Tests;
with Web_Binding_Form_Tests;
with Web_Binding_Validation_Tests;
with Web_Binding_Auth_Tests;
with Web_Binding_Handler_Tests;
with Web_Binding_Hardening_Tests;
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
      Web_Binding_Tests.Add_Tests (Result);
      Web_Binding_Decoder_Tests.Add_Tests (Result);
      Web_Binding_Decoder_Ext_Tests.Add_Tests (Result);
      Web_Binding_Source_Tests.Add_Tests (Result);
      Web_Binding_Record_Tests.Add_Tests (Result);
      Web_Binding_Collection_Tests.Add_Tests (Result);
      Web_Binding_URLEncoded_Tests.Add_Tests (Result);
      Web_Binding_JSON_Tests.Add_Tests (Result);
      Web_Binding_JSON_Bind_Tests.Add_Tests (Result);
      Web_Binding_Union_Tests.Add_Tests (Result);
      Web_Binding_Media_Tests.Add_Tests (Result);
      Web_Binding_Multipart_Tests.Add_Tests (Result);
      Web_Binding_Upload_Tests.Add_Tests (Result);
      Web_Binding_Form_Tests.Add_Tests (Result);
      Web_Binding_Validation_Tests.Add_Tests (Result);
      Web_Binding_Auth_Tests.Add_Tests (Result);
      Web_Binding_Handler_Tests.Add_Tests (Result);
      Web_Binding_Hardening_Tests.Add_Tests (Result);
      Web_E2E_Tests.Add_Tests (Result);
      return Result;
   end Suite;
end Web_Test_Suite;
