<p>Libris ILL requests should normally be initiated in Libris, not in Koha. This form is for entering requests sent outside of Libris.</p>
<p><a href="/cgi-bin/koha/ill/ill-requests.pl">Back to existing requests</a>.</p>

<form method="POST" action="/cgi-bin/koha/ill/ill-requests.pl?method=create">
<fieldset class="rows">
  <legend>Beskrivning</legend>
  <ol>
    <li class="borrowernumber">
      <label for="borrowernumber" class="borrowernumber">Låntagarnummer:</label>
      <input type="text" name="borrowernumber" id="borrowernumber" />
    </li>
    <li class="biblio_id">
      <label for="biblio_id" class="biblio_id">Biblio:</label>
      <input type="text" name="biblio_id" id="biblio_id" />
    </li>
    <li class="medium">
      <label for="medium" class="medium">Lån/kopia:</label>
      <select name="medium" id="medium">
        <option>Lån</option>
        <option>Kopia</option>
      </select>
    </li>
    <li class="accessurl">
      <label for="accessurl" class="accessurl">URL:</label>
      <input type="text" name="accessurl" id="accessurl" />
    </li>
    <li class="cost">
      <label for="cost" class="cost">Kostnad:</label>
      <input type="text" name="cost" id="cost" />
    </li>
    <li class="price_paid">
      <label for="price_paid" class="price_paid">Pris betald:</label>
      <input type="text" name="price_paid" id="price_paid" />
    </li>
    <li class="notesopac">
      <label for="notesopac" class="notesopac">OPAC-note:</label>
      <input type="text" name="notesopac" id="notesopac" />
    </li>
    <li class="notesstaff">
      <label for="notesstaff" class="notesstaff">Intern note:</label>
      <input type="text" name="notesstaff" id="notesstaff" />
    </li>
    <li class="orderid">
      <label for="orderid" class="orderid">Beställnings-ID:</label>
      <input type="text" name="orderid" id="orderid" />
    </li>
    <li class="illtitle">
      <label for="illtitle" class="illtitle">Titel:</label>
      <input type="text" name="illtitle" id="illtitle" />
    </li>
    <li class="author">
      <label for="author" class="author">Författare:</label>
      <input type="text" name="author" id="author" />
    </li>
    <li>
      <input name="stage" id="stage" value="save" type="hidden">
      <input name="method" id="method" value="create" type="hidden">
      <input name="backend" id="backend" value="Libris" type="hidden" />
      <input type="submit" value="Save">
      <a href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&illrequest_id=[% whole.illrequest_id %]">Cancel</a>
    </li>
  </ol>
</fieldset>
</form>
