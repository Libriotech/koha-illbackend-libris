<!-- Error Handling -->
[% IF whole.error %]
    <!-- Dispatch on Status -->
    <p>We encountered an error:</p>
    <ol>
        <li>[% whole.status %]</li>
        <li>[% whole.message %]</li>
    </ol>
[% END %]


[% IF whole.stage == "response" %]

    <p>We gave a response</p>

[% ELSIF whole.stage == "form" %]
    <p>Give response to incoming request.</p>
    <form method="POST" action="/cgi-bin/koha/ill/ill-requests.pl?method=confirm&illrequest_id=506">
    Response:
    <select name="response" id="response">
        <option value="1">Utlånad</option>
        <option value="2">Förkommen</option>
        <option value="3">Utlånas ej</option>
        <option value="4">Finns ej</option>
        <option value="5">F n ej tillgänglig</option>
        <option value="6">Ej anländ</option>
        <option value="7">Reserverad för er</option>
        <option value="8">Övrigt</option>
        <option value="9">Levererad</option>
    </select>
    <br>
    Added response: <input type="text" name="added_response" id="added_response" />
    <br>
    May reserve:
      <input type="radio" name="may_reserve" value="0" checked> Nei
      <input type="radio" name="may_reserve" value="1"> Ja
    <br>
    <input name="stage" id="stage" value="response" type="hidden"/>
    <input name="method" id="method" value="confirm" type="hidden"/>
    <input name="illrequest_id" id="illrequest_id" value="506" type="hidden"/>
    <input type="submit" value="Save">
    </form>
[% ELSE %]
    <p>We encountered an unexpected situation</p>
[% END %]
