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
    <h3>Receive outgoing request number [% whole.illrequest_id %].</h3>
    <form method="POST" action="/cgi-bin/koha/ill/ill-requests.pl?method=receive&illrequest_id=[% whole.illrequest_id %]">
    <fieldset class="rows">
        <legend>Request details</legend>
        <ol>
            <li class="illtitle"> <label class="illtitle">Title:</label>      [% whole.title %]</li>
            <li class="author">   <label class="author">Author:</label>       [% whole.author %]</li>
            <li class="lf_number"><label class="lf_number">LF number:</label> [% whole.lf_number %]</li>
            <li class="type">
                <label class="type">Typ:</label>
                <select name="type" id="type" >
                    [% IF whole.type == 'Lån' %]
                        <option value="Lån" selected="selected">Lån</option>
                    [% ELSE %]
                        <option value="Lån">Lån</option>
                    [% END %]
                    [% IF whole.type == 'Kopia' %]
                        <option value="Kopia" selected="selected">Kopia</option>
                    [% ELSE %]
                        <option value="Kopia">Kopia</option>
                    [% END %]
                </select>
           </li>
           <li class="borrowernumber">
                <label class="borrowernumber">Låntagare:</label>
                [% whole.patron.firstname %] [% whole.patron.surname %]
                <input type="text" name="borrowernumber" id="borrowernumber" size="7" value="[% whole.borrowernumber %]" />
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
                <input type="text" name="due_date_guar" id="due_date_guar" value="[% whole.due_date_guar %]" />
           </li>
            <li class="due_date_max">
                <label class="due_date_max">Lånetid, max:</label>
                <input type="text" name="due_date_max" id="due_date_max" value="[% whole.due_date_max %]" />
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
        <legend>Message - email/print</legend>
        <ol>
            <li class="email_title">
                <label class="email_title">Title:</label>
                <input type="text" name="email_title" id="email_title" value="[% whole.email.title %]" />
           </li>
            <li class="email_content">
                <label class="email_content">Message:</label>
                <textarea name="email_content" id="email_content" rows="10" cols="50">[% whole.email.content %]</textarea>
           </li>
           <li class="send_email">
                <label class="send_email">Send message:</label>
                <input type="radio" name="send_email" value="0" checked> Nei
                <input type="radio" name="send_email" value="1"> Ja
           </li>
        </ol>
    </fieldset>
    [% IF Koha.Preference('SMSSendDriver') %]
        <fieldset class="rows">
            <legend>Message - SMS</legend>
            <ol>
                <li class="sms_title">
                    <label class="sms_title">Title:</label>
                    <input type="text" name="sms_title" id="sms_title" value="[% whole.sms.title %]" />
               </li>
                <li class="sms_content">
                    <label class="sms_content">Message:</label>
                    <textarea name="sms_content" id="sms_content" rows="10" cols="50">[% whole.sms.content %]</textarea>
               </li>
               <li class="send_sms">
                    <label class="send_sms">Send message:</label>
                    <input type="radio" name="send_sms" value="0" checked> Nei
                    <input type="radio" name="send_sms" value="1"> Ja
               </li>
            </ol>
        </fieldset>
    [% END %]
    <fieldset class="rows">
        <legend>Streckkod</legend>
        <ol>
            <li class="ill_barcode">
                <label class="ill_barcode">Streckkod:</label>
                <input type="text" name="ill_barcode" id="ill_barcode" />
                <br><span class="hint">När du läser streckkoden kommer skjemat at skickas in.</span>
            </li>
        </ol>
    </fieldset>
    <fieldset class="action">
        <input name="stage" id="stage" value="receive" type="hidden"/>
        <input name="method" id="method" value="receive" type="hidden"/>
        <input name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id %]" type="hidden"/>
        <input type="hidden" name="letter_code" id="letter_code" value="[% whole.letter_code %]" />
        <input type="submit" value="Motta">
        <a href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&illrequest_id=[% whole.illrequest_id %]">Avbryt</a>
    </fieldset>
    </form>
[% ELSE %]
    <p>We encountered an unexpected situation</p>
[% END %]
