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
    <h3>Respond to incoming request number [% whole.illrequest_id %].</h3>
    <form method="POST" action="/cgi-bin/koha/ill/ill-requests.pl?method=respond&illrequest_id=[% whole.illrequest_id %]">
    [% INCLUDE 'csrf-token.inc' %]
    <fieldset class="rows">
        <legend>Request:</legend>
        <ol>
            <li class="illtitle"> <label class="illtitle">Title:</label>      [% whole.title %]</li>
            <li class="author">   <label class="author">Author:</label>       [% whole.author %]</li>
            <li class="lf_number"><label class="lf_number">LF number:</label> [% whole.lf_number %]</li>
        </ol>
    </fieldset>
    <fieldset class="rows">
        <legend>Response:</legend>
        <ol>
            <li class="response_id">
                <label class="response_id">Response:</label>
                <select name="response_id" id="response_id">
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
            </li>
            <li class="added_response">
                <label class="added_response">Added response:</label>
                <input type="text" name="added_response" id="added_response" />
            </li>
            <li class="may_reserve">
                <label class="may_reserve">May reserve:</label>
                <input type="radio" name="may_reserve" value="0" checked> Nei
                <input type="radio" name="may_reserve" value="1"> Ja
            </li>
            <li class="title">
                <input name="stage" id="stage" value="response" type="hidden"/>
                <input name="method" id="method" value="respond" type="hidden"/>
                <input name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id %]" type="hidden"/>
                <input type="submit" value="Save">
                <a href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&illrequest_id=[% whole.illrequest_id %]">Cancel</a>
            </li>
        </ol>
    </fieldset>
    </form>
[% ELSE %]
    <p>We encountered an unexpected situation</p>
[% END %]
