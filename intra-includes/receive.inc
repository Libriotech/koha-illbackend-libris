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
    <h3>Receive outgoing request number [% whole.illrequest_id %].</h3>
    <form method="POST" action="/cgi-bin/koha/ill/ill-requests.pl?method=respond&illrequest_id=[% whole.illrequest_id %]">
    <fieldset class="rows">
        <legend>Request details</legend>
        <ol>
            <li class="illtitle"> <label class="illtitle">Title:</label>      [% whole.title %]</li>
            <li class="author">   <label class="author">Author:</label>       [% whole.author %]</li>
            <li class="lf_number"><label class="lf_number">LF number:</label> [% whole.lf_number %]</li>
        </ol>
    </fieldset>
    <fieldset class="rows">
        <legend>Receive</legend>
        <ol>
            <li class="ill_barcode">
                <label class="ill_barcode">Barcode:</label>
                <input type="text" name="ill_barcode" id="ill_barcode" />
            </li>
            <li class="title">
                <input name="stage" id="stage" value="receive" type="hidden"/>
                <input name="method" id="method" value="receive" type="hidden"/>
                <input name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id %]" type="hidden"/>
            </li>
        </ol>
    </fieldset>
        <input type="submit" value="Save">
        <a href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&illrequest_id=[% whole.illrequest_id %]">Cancel</a>
    </form>
[% ELSE %]
    <p>We encountered an unexpected situation</p>
[% END %]
