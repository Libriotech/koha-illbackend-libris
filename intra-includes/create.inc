<p>Libris ILL requests should normally be initiated in Libris, not in Koha. This form is for entering requests sent outside of Libris.</p>
<p><a href="/cgi-bin/koha/ill/ill-requests.pl">Back to existing requests</a>.</p>

<form method="POST" action="/cgi-bin/koha/ill/ill-requests.pl?method=create">
<fieldset class="rows">
  <legend>Beskrivning</legend>
  <ol>
    <li class="borrowernumber">
      <label for="borrowernumber" class="borrowernumber">Låntagarnummer:</label>
      <input type="text" name="borrowernumber" id="borrowernumber" /> (Låntagaren som skal ha fjärrlånet.)
    </li>
    <li class="biblio_id">
      <label for="biblio_id" class="biblio_id">Biblionumber:</label>
      <input type="text" name="biblio_id" id="biblio_id" />
    </li>
    <li class="medium">
      <label for="medium" class="medium">Lån/kopia:</label>
      <select name="medium" id="medium">
        <option>Lån</option>
        <option>Kopia</option>
      </select>
    </li>
    <li class="active_library">
      <label for="active_library" class="active_library">Aktivt bibliotek:</label>
      <input type="text" name="active_library" id="active_library" />
    </li>
    <li class="due_date_guar">
      <label for="due_date_guar" class="due_date_guar">Lånetid, garanterad:</label>
      <input type="text" name="due_date_guar" id="due_date_guar" />
    </li>
    <li class="due_date_max">
      <label for="due_date_max" class="due_date_max">Lånetid, max:</label>
      <input type="text" name="due_date_max" id="due_date_max" />
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
    <li class="orderid">
      <label for="orderid" class="orderid">Beställnings-ID:</label>
      <input type="text" name="orderid" id="orderid" />
    </li>
    <li class="message">
      <label for="message" class="message">Anmärkning:</label>
      <input type="text" name="message" id="message" />
    </li>
</fieldset>
<fieldset class="rows">
    <legend>Noter</legend>
    <ol>
    <li class="notesopac">
      <label for="notesopac" class="notesopac">OPAC-kommentar (till låntagaren):</label>
      <textarea name="notesopac" id="notesopac" rows="10" cols="50"></textarea>
    </li>
    <li class="notesstaff">
      <label for="notesstaff" class="notesstaff">Internkommentar:</label>
      <textarea name="notesstaff" id="notesstaff" rows="10" cols="50"></textarea>
    </li>
    </ol>
</fieldset>
<fieldset class="rows">
    <legend>Bibliografiska detaljer</legend>
    <ol>
    <li class="illtitle">
      <label for="illtitle" class="illtitle">Titel:</label>
      <input type="text" name="illtitle" id="illtitle" />
    </li>
    <li class="author">
      <label for="author" class="author">Författare:</label>
      <input type="text" name="author" id="author" />
    </li>
    <li class="year">
      <label for="year" class="year">År:</label>
      <input type="text" name="year" id="year" />
    </li>
    <li class="volume">
      <label for="volume" class="volume">Volume:</label>
      <input type="text" name="volume" id="volume" />
    </li>
    <li class="part">
      <label for="part" class="part">Del / utgåva:</label>
      <input type="text" name="part" id="part" />
    </li>
    <li class="isbn_issn">
      <label for="isbn_issn" class="isbn_issn">ISBN/ISSN:</label>
      <input type="text" name="isbn_issn" id="isbn_issn" />
    </li>
    </ol>
</fieldset>
<fieldset class="rows">
    <legend>Artikkel/kapitel/del</legend>
    <ol>
    <li class="arttitle">
      <label for="arttitle" class="arttitle">Titel:</label>
      <input type="text" name="arttitle" id="arttitle" />
    </li>
    <li class="artauthor">
      <label for="artauthor" class="artauthor">Författare:</label>
      <input type="text" name="artauthor" id="artauthor" />
    </li>
    <li class="pages">
      <label for="pages" class="pages">Sidor:</label>
      <input type="text" name="pages" id="pages" />
    </li>
  </ol>
</fieldset>
<fieldset class="rows">
    <legend>Handläggare</legend>
    <ol>
    <li class="librarian">
      <label for="librarian" class="librarian">Handläggare:</label>
      <input type="text" name="librarian" id="librarian" />
    </li>
  </ol>
</fieldset>
      <input name="stage" id="stage" value="save" type="hidden">
      <input name="method" id="method" value="create" type="hidden">
      <input name="backend" id="backend" value="Libris" type="hidden" />
      <input type="submit" value="Save">
      <a href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&illrequest_id=[% whole.illrequest_id %]">Cancel</a>
</form>
