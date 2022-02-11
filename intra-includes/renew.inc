[% USE Categories %]

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
    <h3>Renew request number [% whole.illrequest_id %].</h3>
    <form method="POST" action="/cgi-bin/koha/ill/ill-requests.pl?method=renew&illrequest_id=[% whole.illrequest_id %]">
    <fieldset class="rows">
        <legend>Request details</legend>
        <ol>
            <li class="illtitle"> <label class="illtitle">Title:</label>      [% whole.title %]</li>
            <li class="author">   <label class="author">Author:</label>       [% whole.author %]</li>
            <li class="lf_number"><label class="lf_number">LF number:</label> [% whole.lf_number %]</li>
            <li class="type">     <label class="type">Typ:</label>            [% whole.type %]</li>
           <li class="borrowernumber">
                <label class="borrowernumber">Låntagare:</label>
                [% whole.patron.firstname %] [% whole.patron.surname %]
           </li>
           <li class="categorycode">
                <label class="categorycode">Kategori:</label>
                <span id="categorycode">[% Categories.GetName( whole.categorycode ) | html %] ([% whole.categorycode %])</span>
           </li>
           <li class="active_library">
                <label class="active_library">Långivande bibliotek:</label>
                <input type="text" name="active_library" id="active_library" value="[% whole.active_library %]" />
           </li>
        </ol>
    </fieldset>
    <fieldset class="rows">
        <legend>Lånetid</legend>
        <ol>
            <li class="due_date_guar">
                <label class="due_date_guar">Lånetid, garanterad:</label>
                <input type="text" name="due_date_guar" id="due_date_guar" class="flatpickr" value="[% whole.due_date_guar %]" />
           </li>
            <li class="due_date_max">
                <label class="due_date_max">Lånetid, max:</label>
                <input type="text" name="due_date_max" id="due_date_max" class="flatpickr" value="[% whole.due_date_max %]" />
           </li>
        </ol>
    </fieldset>
    <fieldset class="rows">
        <legend>Fee</legend>
        <ol>
            <li class="ill_charge">
                <label class="ill_charge">Fee:</label>
                <input type="text" name="ill_charge" id="ill_charge" value="[% whole.ill_charge %]" />
            </li>
            <li class="ill_charge_type">
                <label class="ill_charge_type">Type:</label>
                <select name="ill_charge_type">
                    [% FOREACH charge_type IN whole.ill_charge_types %]
                    <option value="[% charge_type.code %]">[% charge_type.description %]</option>
                    [% END %]
                </select>
            </li>
            <li class="ill_charge_description">
                <label class="ill_charge_description">Fee description:</label>
                <input type="text" name="ill_charge_description" id="ill_charge_description" value="[% whole.ill_charge_description %]" />
            </li>
        </ol>
    </fieldset>
    <fieldset class="rows">
        <legend>Comment</legend>
        <ol>
            <li class="comment">
                <label class="comment">Comment:</label>
                <textarea name="comment" id="comment" rows="10" cols="50"></textarea>
           </li>
        </ol>
    </fieldset>
    <fieldset class="action">
        <input name="stage" id="stage" value="renew" type="hidden"/>
        <input name="method" id="method" value="renew" type="hidden"/>
        <input name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id %]" type="hidden"/>
        <input type="hidden" name="letter_code" id="letter_code" value="[% whole.letter_code %]" />
        <input type="submit" value="Save">
        <a href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&illrequest_id=[% whole.illrequest_id %]">Avbryt</a>
    </fieldset>
    </form>
[% ELSE %]
    <p>We encountered an unexpected situation</p>
[% END %]
