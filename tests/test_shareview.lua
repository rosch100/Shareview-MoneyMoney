---@diagnostic disable: duplicate-set-field -- Testfälle überschreiben Connection-Mocks absichtlich.
-- Lokaler Funktions-Test der Shareview-Parser gegen die echten HAR-Daten.
-- Lädt die Extension nicht über die WebBanking-Engine, sondern stubbt
-- die nötigen Globals und prüft Parser-Ausgaben.

-- WebBanking/Connection/MM stubben
function WebBanking(_) end

ProtocolWebBanking = "WebBanking"
AccountTypePortfolio = 5
LoginFailed = "LoginFailed"

MM = {
  printStatus = function(msg) io.stderr:write("[STATUS] " .. msg .. "\n") end,
  urlencode = function(s)
    return (tostring(s):gsub("([^%w%-%.%_%~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end))
  end
}

function Connection() return { request = function() end, getCookies = function() return "" end } end

-- Extension laden
dofile("Shareview.lua")

local function assertEq(actual, expected, label)
  if actual == expected then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print("FAIL  " .. label .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    os.exit(1)
  end
end

local function assertNear(actual, expected, label)
  local eps = 0.001
  if math.abs((actual or 0) - expected) < eps then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print("FAIL  " .. label .. ": expected~" .. tostring(expected) .. ", actual=" .. tostring(actual))
    os.exit(1)
  end
end

-- Test: parseUsernameDob (Pipe-Komfort-Pfad)
local user, d, m, y = parseUsernameDob("rosch100|01.01.1970")
assertEq(user, "rosch100", "parseUsernameDob.user")
assertEq(d, 1, "parseUsernameDob.day")
assertEq(m, 1, "parseUsernameDob.month")
assertEq(y, 1970, "parseUsernameDob.year")

-- Username ohne Pipe → DOB wird per Multi-Step nachgefragt
local u2, d2 = parseUsernameDob("user")
assertEq(u2, "user", "parseUsernameDob.user-only.name")
assertEq(d2, nil, "parseUsernameDob.user-only.day=nil")

local u3, d3, m3, y3 = parseUsernameDob("rosch100|1/1/1970")
assertEq(u3, "rosch100", "parseUsernameDob.slash.user")
assertEq(d3, 1, "parseUsernameDob.slash.day")
assertEq(y3, 1970, "parseUsernameDob.slash.year")

local u4, d4 = parseUsernameDob("name|invalid")
assertEq(u4, "name", "parseUsernameDob.invalid.user")
assertEq(d4, nil, "parseUsernameDob.invalid.day=nil")

-- Test: parseDobString (standalone, für Multi-Step-Eingabe)
local dx, mx, yx = parseDobString("01.01.1970")
assertEq(dx, 1, "parseDobString.dotted.day")
assertEq(mx, 1, "parseDobString.dotted.month")
assertEq(yx, 1970, "parseDobString.dotted.year")

local ds, ms, ys = parseDobString("  1/1/1970  ")
assertEq(ds, 1, "parseDobString.trim+slash.day")
assertEq(ys, 1970, "parseDobString.trim+slash.year")

local dh, mh, yh = parseDobString("1-1-1970")
assertEq(dh, 1, "parseDobString.dash.day")
assertEq(yh, 1970, "parseDobString.dash.year")

local dn = parseDobString("garbage")
assertEq(dn, nil, "parseDobString.garbage.day=nil")

local dnil = parseDobString(nil)
assertEq(dnil, nil, "parseDobString.nil.day=nil")

-- Test: isValidDob (Range-Check)
assertEq(isValidDob(1, 1, 1970), true, "isValidDob.normal")
assertEq(isValidDob(31, 12, 2099), true, "isValidDob.edge.upper")
assertEq(isValidDob(1, 1, 1900), true, "isValidDob.edge.lower")
assertEq(isValidDob(0, 1, 1970), false, "isValidDob.day=0")
assertEq(isValidDob(32, 1, 1970), false, "isValidDob.day=32")
assertEq(isValidDob(1, 0, 1970), false, "isValidDob.month=0")
assertEq(isValidDob(1, 13, 1970), false, "isValidDob.month=13")
assertEq(isValidDob(1, 1, 1899), false, "isValidDob.year=1899")
assertEq(isValidDob(1, 1, 2101), false, "isValidDob.year=2101")
assertEq(isValidDob(nil, 1, 1970), false, "isValidDob.nil.day")

-- Test: parseCurrencyValue (GBX → GBP)
local amount, native, raw = parseCurrencyValue("GBX|247.0000|99|1|.|,|6")
assertNear(amount, 2.47, "parseCurrencyValue.GBX.price.gbp")
assertEq(native, "GBX", "parseCurrencyValue.GBX.native")
assertNear(raw, 247.0, "parseCurrencyValue.GBX.raw")

local amount2, native2 = parseCurrencyValue("GBP|1000.00000000||0|.|,|")
assertNear(amount2, 1000.00, "parseCurrencyValue.GBP.amount")
assertEq(native2, "GBP", "parseCurrencyValue.GBP.native")

local amount3, native3 = parseCurrencyValue("GBX|100000.0000||0|.|,|")
assertNear(amount3, 1000.00, "parseCurrencyValue.GBX.value.gbp")
assertEq(native3, "GBX", "parseCurrencyValue.GBX.value.native")

-- Test: parseHoldings/parseTotalIndicativeValue gegen echtes HAR-HTML
do
  -- Inline Fixture: bewusst minimal, aber so aufgebaut, dass die Regex/XPath-Matches
  -- in `parseTotalIndicativeValue` und `parseHoldingRow` exakt greifen.
  local html = [[
<div id="TotalIndicativeValue"><span class="currencyChange">GBP|1000.00000000||0|.|,|</span></div>
<table>
  <tr class="summaryDataItemRow" id="row1">
    <td headers="holding"><strong>Example Corp (Share Account)</strong><br/>Shareholder Ref No:1234567890</td>
    <td headers="quantity"><bdo>100</bdo></td>
    <td headers="price"><span class="original">GBX|1000.0000|99|1|.|,|6</span></td>
    <td headers="value"><span class="original">GBP|1000.00000000||0|.|,|</span></td>
    externalid=GB0000000001
  </tr>
</table>
]]

  local total, totalCcy = parseTotalIndicativeValue(html)
  assertNear(total, 1000.00, "parseTotalIndicativeValue.amount")
  assertEq(totalCcy, "GBP", "parseTotalIndicativeValue.currency")

  local secs = parseHoldings(html)
  assertEq(#secs, 1, "parseHoldings.count")

  local s = secs[1]
  print()
  print("Erste Position:")
  for k, v in pairs(s) do
    print(string.format("  %-26s = %s", k, tostring(v)))
  end

  assertEq(s.name, "Example Corp (Share Account)", "parseHoldings.name")
  assertEq(s.isin, "GB0000000001", "parseHoldings.isin")
  assertEq(s.securityNumber, "1234567890", "parseHoldings.securityNumber")
  assertEq(s.quantity, 100, "parseHoldings.quantity")
  assertNear(s.price, 10.00, "parseHoldings.price")
  assertNear(s.amount, 1000.00, "parseHoldings.amount")
  assertEq(s.currencyOfPrice, "GBP", "parseHoldings.currencyOfPrice")
  assertEq(s.currencyOfOriginalAmount, "GBP", "parseHoldings.currencyOfOriginalAmount")
end

-- Additional edge cases (Coverage)
do
  -- parseCurrencyValue: nil / ungültig
  local a, b, c = parseCurrencyValue(nil)
  assertEq(a, nil, "parseCurrencyValue.nil.amount")
  assertEq(b, nil, "parseCurrencyValue.nil.currency")
  assertEq(c, nil, "parseCurrencyValue.nil.nativeAmount")

  local a2, b2, c2 = parseCurrencyValue("NOTACCUR|abc")
  assertEq(a2, nil, "parseCurrencyValue.invalid.amount")
  assertEq(b2, nil, "parseCurrencyValue.invalid.currency")
  assertEq(c2, nil, "parseCurrencyValue.invalid.nativeAmount")

  -- parseHoldings: nil input -> leere Liste
  local secs = parseHoldings(nil)
  assertEq(#secs, 0, "parseHoldings.nil=empty")

  -- parseHoldingRow: invalid ISIN (wrong format) -> empty string
  local html2 = [[
<table>
  <tr class="summaryDataItemRow" id="row2">
    <td headers="holding"><strong>Example Position</strong><br/>Shareholder Ref No:REF-123</td>
    <td headers="quantity"><bdo>1</bdo></td>
    <td headers="price"><span class="original">GBX|100.0000|99|1|.|,|6</span></td>
    <td headers="value"><span class="original">GBP|1.00||0|.|,|</span></td>
    externalid=INVALID_ISIN
  </tr>
</table>
]]
  local secs2 = parseHoldings(html2)
  assertEq(#secs2, 1, "parseHoldings.count.invalid-isin")
  assertEq(secs2[1].name, "Example Position", "parseHoldingRow.htmlDecode.name")
  assertEq(secs2[1].isin, "", "parseHoldingRow.invalid-isin=empty")

  local incomplete, incompleteCount = parseHoldings([[
<table>
  <tr class="summaryDataItemRow">
    <td headers="holding"><strong>Incomplete Position</strong></td>
  </tr>
</table>
]])
  assertEq(#incomplete, 0, "parseHoldings.incompletePositionOmitted")
  assertEq(incompleteCount, 1, "parseHoldings.incompletePositionReported")
end

-- extractLoginError / isLoggedInPage / isMfaPage
do
  local function nodeWithText(text)
    return { text = function() return text end }
  end

  local htmlNode = {
    xpath = function(_, xp)
      if xp:find("ErrorMessage", 1, true) then
        return nodeWithText("  Something went wrong  ")
      end
      return nil
    end
  }

  local err = extractLoginError(htmlNode)
  assertEq(err, "Something went wrong", "extractLoginError.trim")

  local htmlNode2 = {
    xpath = function(_, xp)
      -- return only whitespace -> should be ignored, then return nil
      return nodeWithText("   ")
    end
  }
  local err2 = extractLoginError(htmlNode2)
  assertEq(err2, nil, "extractLoginError.whitespace=nil")

  assertEq(isLoggedInPage('noTotal but id="TotalIndicativeValue"'), true, "isLoggedInPage.TotalIndicativeValue")
  assertEq(isLoggedInPage("My Holdings Summary"), true, "isLoggedInPage.MyHoldingsSummary")
  assertEq(isMfaPage("Bitte authentication code eingeben"), true, "isMfaPage.authentication-code")
  assertEq(isMfaPage(nil), false, "isMfaPage.nil=false")
end

assertEq(type(isCredentialRejectionMessage), "function",
  "isCredentialRejectionMessage.available")
assertEq(
  isCredentialRejectionMessage("The username or password entered is incorrect."),
  true,
  "isCredentialRejectionMessage.password")
assertEq(
  isCredentialRejectionMessage("The service is temporarily unavailable."),
  false,
  "isCredentialRejectionMessage.technical")

assertEq(shareviewLoginUsername("alice|01.01.1970"), "alice", "shareviewLoginUsername.pipe")
assertEq(shareviewLoginUsername("bob"), "bob", "shareviewLoginUsername.plain")
assertEq(shareviewAccountNumberForUsername("alice"), "SV.alice", "shareviewAccountNumber")
assertEq(shareviewAccountNameForUsername("alice"), "Shareview (alice)", "shareviewAccountName")
assertEq(isLegacyShareviewAccountNumber("shareview-portfolio"), true, "legacyAccountNumber")
assertEq(
  knownAccountsIncludeLegacyShareview({{accountNumber = "shareview-portfolio"}}),
  true,
  "knownAccountsIncludeLegacy")
assertEq(
  knownAccountsIncludeLegacyShareview({{accountNumber = "SV.alice"}}),
  false,
  "knownAccountsExcludeSv")

local firstConnection = {
  language = "",
  useragent = "",
  get = function() return nil end,
}
Connection = function()
  return firstConnection
end
LocalStorage = {}
local dobChallenge = InitializeSession2(
  ProtocolWebBanking,
  "Shareview",
  1,
  {"restore-user", "password"},
  true)
assertEq(type(dobChallenge), "table", "InitializeSession2.dobChallenge")
assertEq(
  LocalStorage.connectionsByAccount["restore-user"].connection,
  firstConnection,
  "InitializeSession2.connectionMap")
assertEq(LocalStorage.connectionAccountKey, "restore-user",
  "InitializeSession2.connectionAccountKey")
local restoredConnection = {
  language = "",
  useragent = "",
  get = function() return nil end,
}
LocalStorage.connectionsByAccount["restore-user"] = { connection = restoredConnection }
LocalStorage.connection = restoredConnection
LocalStorage.connectionAccountKey = "restore-user"
InitializeSession2(
  ProtocolWebBanking,
  "Shareview",
  2,
  {"invalid-date"},
  true)
assertEq(restoredConnection.language, "en-GB",
  "InitializeSession2.restoresConnectionForStep2")
local refreshOk, refreshError = pcall(
  RefreshAccount,
  {accountNumber = "SV.restore-user"},
  nil)
assertEq(refreshOk, false, "RefreshAccount.propagatesFailure")
assertEq(
  type(refreshError) == "string"
    and refreshError:find("Kontoabruf", 1, true) ~= nil,
  true,
  "RefreshAccount.failureMessage")
restoredConnection.get = function()
  return "<html><body>Sign in</body></html>"
end
local unauthenticatedOk, unauthenticatedError = pcall(
  RefreshAccount,
  {accountNumber = "SV.restore-user"},
  nil)
assertEq(unauthenticatedOk, false, "RefreshAccount.rejectsUnauthenticatedPage")
assertEq(
  type(unauthenticatedError) == "string"
    and unauthenticatedError:find("nicht authentifiziert", 1, true) ~= nil,
  true,
  "RefreshAccount.unauthenticatedMessage")
restoredConnection.get = function()
  return [[
<html><body>
  <div id="TotalIndicativeValue"><span class="currencyChange">GBP|100.00||0|.|,|</span></div>
  <table>
    <tr class="summaryDataItemRow">
      <td headers="holding"><strong>Incomplete Position</strong></td>
    </tr>
  </table>
</body></html>
]]
end
InitializeSession2(
  ProtocolWebBanking,
  "Shareview",
  1,
  {"restore-user", "password"},
  true)
local incompletePortfolioOk, incompletePortfolioError = pcall(
  RefreshAccount,
  {accountNumber = "SV.restore-user"},
  nil)
assertEq(incompletePortfolioOk, false, "RefreshAccount.rejectsIncompletePortfolio")
assertEq(
  type(incompletePortfolioError) == "string"
    and incompletePortfolioError:find("Portfoliodaten", 1, true) ~= nil,
  true,
  "RefreshAccount.incompletePortfolioMessage")

local missingTotalHtml = [[
<html><body>
  <h1>My Holdings Summary</h1>
  <table>
    <tr class="summaryDataItemRow" id="row1">
      <td headers="holding"><strong>Example Corp</strong><br/>Shareholder Ref No:1234567890</td>
      <td headers="quantity"><bdo>100</bdo></td>
      <td headers="price"><span class="original">GBX|1000.0000|99|1|.|,|6</span></td>
      <td headers="value"><span class="original">GBP|1000.00000000||0|.|,|</span></td>
      externalid=GB0000000001
    </tr>
  </table>
</body></html>
]]
local missingTotalSecurities, missingTotalIncomplete = parseHoldings(missingTotalHtml)
assertEq(#missingTotalSecurities, 1, "RefreshAccount.missingTotalFixturePosition")
assertEq(missingTotalIncomplete, 0, "RefreshAccount.missingTotalFixtureComplete")
restoredConnection.get = function()
  return missingTotalHtml
end
local missingTotalPortfolio = RefreshAccount(
  {accountNumber = "SV.restore-user"},
  nil)
assertEq(missingTotalPortfolio.balance, nil, "RefreshAccount.omitsMissingOptionalTotal")
assertEq(#missingTotalPortfolio.securities, 1, "RefreshAccount.keepsCompletePositionsWithoutTotal")

restoredConnection.get = function()
  return '<html><body><div id="TotalIndicativeValue"><span>GBP|100.00||0|.|,|</span></div></body></html>'
end
local missingHoldingsMarkupOk, missingHoldingsMarkupError = pcall(
  RefreshAccount,
  {accountNumber = "SV.restore-user"},
  nil)
assertEq(missingHoldingsMarkupOk, false, "RefreshAccount.rejectsMissingHoldingsMarkup")
assertEq(
  type(missingHoldingsMarkupError) == "string"
    and missingHoldingsMarkupError:find("Positionsbereich", 1, true) ~= nil,
  true,
  "RefreshAccount.missingHoldingsMarkupMessage")

local function holdingsPage(balance)
  return '<html><body><h1>My Holdings Summary</h1>'
    .. '<div id="TotalIndicativeValue"><span>GBP|'
    .. tostring(balance)
    .. '||0|.|,|</span></div>'
    .. '<table><tr class="summaryDataItemRow">'
    .. '<td headers="holding"><strong>Example Corp</strong><br/>Shareholder Ref No:1234567890</td>'
    .. '<td headers="quantity"><bdo>1</bdo></td>'
    .. '<td headers="price"><span class="original">GBP|' .. tostring(balance) .. '||0|.|,|</span></td>'
    .. '<td headers="value"><span class="original">GBP|' .. tostring(balance) .. '||0|.|,|</span></td>'
    .. 'externalid=GB0000000001</tr></table></body></html>'
end

restoredConnection.get = function()
  return holdingsPage("100.00")
end
InitializeSession2(
  ProtocolWebBanking,
  "Shareview",
  1,
  {"restore-user", "password"},
  true)

local invalidAccountOk, invalidAccountError = pcall(RefreshAccount, nil, nil)
assertEq(invalidAccountOk, false, "RefreshAccount.rejectsInvalidAccount")
assertEq(
  type(invalidAccountError) == "string"
    and invalidAccountError:find("Kontoabruf", 1, true) ~= nil,
  true,
  "RefreshAccount.invalidAccountMessage")

restoredConnection.get = function()
  return holdingsPage("200.00")
end
local legacyOk, legacyPortfolio = pcall(
  RefreshAccount,
  {accountNumber = "shareview-portfolio"},
  nil)
assertEq(legacyOk, true, "RefreshAccount.acceptsLegacyAccountNumber")
assertEq(legacyPortfolio.balance, 200, "RefreshAccount.legacyFetchesHoldings")

local freshPortfolio = RefreshAccount(
  {accountNumber = "SV.restore-user"},
  nil)
assertEq(freshPortfolio.balance, 200, "RefreshAccount.fetchesFreshHoldings")

-- Multi-login: two accountKeys keep distinct connections in the map
do
  local connA = { language = "", useragent = "", get = function() return nil end }
  local connB = { language = "", useragent = "", get = function() return nil end }
  local created = 0
  Connection = function()
    created = created + 1
    if created == 1 then return connA end
    if created == 2 then return connB end
    return { language = "", useragent = "", get = function() return nil end }
  end
  LocalStorage = {}
  InitializeSession2(ProtocolWebBanking, "Shareview", 1, {"user-a|01.01.1970", "pw"}, true)
  assertEq(LocalStorage.connectionsByAccount["user-a"].connection, connA, "multiLogin.map.userA")
  assertEq(shareviewAccountNumberForUsername("user-a"), "SV.user-a", "multiLogin.accountNumber.userA")
  InitializeSession2(ProtocolWebBanking, "Shareview", 1, {"user-b|02.02.1980", "pw"}, true)
  assertEq(LocalStorage.connectionsByAccount["user-b"].connection, connB, "multiLogin.map.userB")
  assertEq(LocalStorage.connectionsByAccount["user-a"].connection, connA, "multiLogin.map.userA.kept")
  assertEq(LocalStorage.connectionAccountKey, "user-b", "multiLogin.activeKey.userB")
  InitializeSession2(ProtocolWebBanking, "Shareview", 1, {"user-a|01.01.1970", "pw"}, true)
  assertEq(LocalStorage.connection, connA, "multiLogin.reusesUserA")
  assertEq(LocalStorage.connectionAccountKey, "user-a", "multiLogin.activeKey.userA")
  EndSession()
end

-- After MoneyMoney restart: Connection gone, FedAuth cookie string must restore session
do
  local holdingsHtml = [[
<html><body>
  <div id="TotalIndicativeValue"><span>GBP|10.00||0|.|,|</span></div>
  <h1>My Holdings Summary</h1>
</body></html>
]]
  local applied = {}
  local cookieApplied = false
  local mockConn = {
    language = "",
    useragent = "",
    getCookies = function()
      if cookieApplied then
        return "FedAuth=TOKEN123"
      end
      return ""
    end,
    setCookie = function(_, value)
      applied[#applied + 1] = value
      if tostring(value):match("FedAuth=") then
        cookieApplied = true
      end
    end,
    get = function()
      if cookieApplied then
        return holdingsHtml
      end
      return "<html><body>Please log in</body></html>"
    end,
  }
  Connection = function() return mockConn end
  LocalStorage = {
    connectionsByAccount = {
      ["cookie-user"] = {
        sessionCookies = "FedAuth=TOKEN123; Path=/",
      },
    },
    sessionCookies = "FedAuth=TOKEN123; Path=/",
    sessionAccountKey = "cookie-user",
  }
  local result = InitializeSession2(
    ProtocolWebBanking,
    "Shareview",
    1,
    {"cookie-user|01.01.1970", "pw"},
    true)
  assertEq(result, nil, "cookieRestore.afterRestart.noLogin")
  assertEq(#applied > 0, true, "cookieRestore.afterRestart.setCookie")
  assertEq(
    LocalStorage.connectionsByAccount["cookie-user"].sessionCookies:match("FedAuth=") ~= nil,
    true,
    "cookieRestore.afterRestart.persisted")
  EndSession()
  assertEq(
    LocalStorage.connectionsByAccount["cookie-user"].sessionCookies:match("FedAuth=") ~= nil,
    true,
    "cookieRestore.endSession.keepsCookies")
end

-- ListAccounts keeps legacy number when MoneyMoney already knows it
do
  local holdingsHtml = [[
<html><body>
  <div id="TotalIndicativeValue"><span>GBP|10.00||0|.|,|</span></div>
  <h1>My Holdings Summary</h1>
</body></html>
]]
  local mockConn = {
    language = "",
    useragent = "",
    get = function() return holdingsHtml end,
  }
  Connection = function() return mockConn end
  LocalStorage = {}
  InitializeSession2(
    ProtocolWebBanking,
    "Shareview",
    1,
    {"legacy-user", "password"},
    true)
  -- Force logged-in holdings into session via ListAccounts path
  local accountsNew = ListAccounts({})
  assertEq(type(accountsNew), "table", "ListAccounts.new.type")
  assertEq(accountsNew[1].accountNumber, "SV.legacy-user", "ListAccounts.new.svNumber")
  local accountsLegacy = ListAccounts({{accountNumber = "shareview-portfolio"}})
  assertEq(accountsLegacy[1].accountNumber, "shareview-portfolio", "ListAccounts.keepsLegacyNumber")
  EndSession()
end

EndSession()
local authFailures = {}
local function checkAuthError(value, label)
  if type(value) == "string" and value ~= "" and value ~= LoginFailed then
    print("OK    " .. label)
  else
    authFailures[#authFailures + 1] = label .. "=" .. tostring(value)
    print("FAIL  " .. label)
  end
end
local missingSession = InitializeSession2(
  ProtocolWebBanking,
  "Shareview",
  2,
  {"123456"},
  true)
checkAuthError(missingSession, "InitializeSession2.missingSession.transient")

local missingPassword = loginStep1({"user", ""}, true)
checkAuthError(missingPassword, "loginStep1.missingPassword.validation")

EndSession()
local missingDobSession = submitDobAndLogin("01.01.1970")
checkAuthError(missingDobSession, "submitDobAndLogin.missingSession.transient")

EndSession()
local missingMfaSession = submitMfaCode({"123456"})
checkAuthError(missingMfaSession, "submitMfaCode.missingSession.transient")
if #authFailures > 0 then
  error("Auth error classification failed: " .. table.concat(authFailures, ", "))
end

-- Federation host allowlist (Adams whitelist)
do
  local _, missingAction = checkFederationFormAction("")
  assertEq(missingAction, "Federation-Hop: Form action fehlt", "federation.missingAction")

  local equinitiUrl, equinitiErr = checkFederationFormAction("https://www.equiniti.com/adfs/ls/")
  assertEq(equinitiErr, nil, "federation.equiniti.err")
  assertEq(equinitiUrl, "https://www.equiniti.com/adfs/ls/", "federation.equiniti.url")

  local trustUrl, trustErr = checkFederationFormAction("https://portfolio.shareview.co.uk:443/_trust/")
  assertEq(trustErr, nil, "federation.trust.err")
  assertEq(trustUrl, "https://portfolio.shareview.co.uk:443/_trust/", "federation.trust.url")

  local relUrl, relErr = checkFederationFormAction("/_trust/")
  assertEq(relErr, nil, "federation.relative.err")
  assertEq(relUrl, "https://portfolio.shareview.co.uk/_trust/", "federation.relative.url")

  local _, foreignErr = checkFederationFormAction("https://evil.example/x")
  assertEq(
    type(foreignErr) == "string"
      and foreignErr:find("nicht erlaubtem Host", 1, true) ~= nil,
    true,
    "federation.foreignHost")

  local _, httpErr = checkFederationFormAction("http://www.equiniti.com/adfs/ls/")
  assertEq(
    type(httpErr) == "string"
      and httpErr:find("https", 1, true) ~= nil,
    true,
    "federation.httpRejected")

  local holdingsCalls = 0
  local mockConn = {
    language = "",
    useragent = "",
    get = function()
      holdingsCalls = holdingsCalls + 1
      return "<html></html>"
    end,
    getCookies = function() return "" end,
  }
  Connection = function()
    return mockConn
  end
  LocalStorage = {}
  InitializeSession2(
    ProtocolWebBanking,
    "Shareview",
    1,
    {"federation-allowlist-user", "password"},
    true)
  holdingsCalls = 0
  local hopFail = finishMfaAfterFederation(
    nil,
    "Federation-Hop zu nicht erlaubtem Host: evil.example")
  assertEq(
    hopFail,
    "Federation-Hop zu nicht erlaubtem Host: evil.example",
    "finishMfaAfterFederation.propagatesErr")
  assertEq(holdingsCalls, 0, "finishMfaAfterFederation.noHoldingsOnErr")
  EndSession()
end

print()
print("ALL TESTS PASSED")
