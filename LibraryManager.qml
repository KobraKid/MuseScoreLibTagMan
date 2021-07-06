import QtQuick 2.7
import QtQuick.Controls 2.2
import QtQuick.Dialogs 1.2
import Qt.labs.folderlistmodel 2.1
import MuseScore 3.0
import FileIO 3.0

MuseScore {
  id: libMan
  menuPath: "Plugins.Library Manager"
  description: "Manage Your Library"
  version: "1.0"
  requiresScore: false
  pluginType: "dock"
  dockArea: "right"
  width: 400
  height: 600

  property var pluginPath: Qt.resolvedUrl(".").substring(8, Qt.resolvedUrl(".").length);
  property var dbPath: pluginPath + "db.json";
  property var db;
  property var isTagEditOpen: false;
  property var uidOpenedTagEdit;
  property var filteredAllowlist;

  onRun: {
    // Get database (or create one)
    if (dbFile.exists()) {
      console.log("database found");
    } else {
      console.log("generating database");
      saveData();
    }
    db = JSON.parse(dbFile.read());

    filteredAllowlist = [];
    populateScoreList();
  }

  /**
   * Populates score list from database
   */
  function populateScoreList() {
    // Remove filtered/deleted scores
    for (var i = scoreListModel.count - 1; i >= 0; i--) {
      var exists = false;
      for (var j = 0; j < db.scores.length; j++) {
        if (scoreListModel.get(i).file === db.scores[j].file && isAllowed(db.scores[j].uid)) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        scoreListModel.remove(i, 1);
      }
    }
    // Add new scores
    for (var i = 0; i < db.scores.length; i++) {
      var inserted = false
      for (var j = 0; j < scoreListModel.count; j++) {
        if (!isAllowed(db.scores[i].uid)) {
          // don't append - not allowed by filter
          inserted = true;
          break;
        }
        if (scoreListModel.get(j).file === db.scores[i].file) {
          // don't append - already in list
          inserted = true;
          break;
        }
        if (scoreListModel.get(j).title > db.scores[i].title) {
          scoreListModel.insert(j, db.scores[i]);
          inserted = true;
          break;
        }
      }
      if (!inserted) {
        scoreListModel.append(db.scores[i]);
      }
    }
    // Update score count
    libraryCount.text = db.scores.length + " Scores" + (scoreListModel.count < db.scores.length ? ". Showing " + scoreListModel.count : "");
  }

  /**
   * Searches specified folder for scores not yet in the database
   *
   * folder - the folder containing scores to add
   */
  function addFilesToDatabase(folder) {
    for (var i = 0; i < folder.count; i++) {
      if (!folder.isFolder(i)) {
        var score = {
          uid: db.nextId,
          file: folder.get(i, "filePath"),
          title: folder.get(i, "fileBaseName")
        };
        if (db.scores.filter(function (s) { return s.file === score.file; }).length === 0) {
          console.log("adding " + score.title);
          db.scores.push(score);
          db.nextId++;
        }
      }
    }
    saveData();
    populateScoreList();
  }

  /**
   * Saves database to file
   */
  function saveData() {
    dbFile.write(JSON.stringify(db));
  }

  /**
   * Performs database clean-up
   */
  function tidyDb() {
    // TODO check for and delete missing files
    // TODO reset nextId and reassign uids if they grow too large
    // TODO check for and remove empty indices
  }

  /**
   * Searches the database for the given term
   *
   * searchTerm - the string to search for
   *              can be either a search by name (e.g. "la bam" will match "La Bamba")
   *              or a prefix:tag format (e.g. "key:c minor" will match "Symphony No. 5 [Beethoven]")
   */
  function searchDB(searchTerm) {
    // prefix:tag format
    if (searchTerm.includes(":")) {
      var splitSearch = searchTerm.split(":");
      if (splitSearch.length !== 2) return; // invalid search term
      var prefix = splitSearch[0].toLowerCase().trim();
      var tag = splitSearch[1].toLowerCase().trim();
      filteredAllowlist = [];
      if (db[prefix] !== undefined) {
        for (var i = 0; i < db[prefix].length; i++) {
          if (db[prefix][i].tag.toLowerCase() === tag) {
            console.log("found score ids: " + db[prefix][i].scores);
            filteredAllowlist.push.apply(filteredAllowlist, db[prefix][i].scores);
            break;
          }
        }
      }
    }
    // just search by name
    else {
      var search = searchTerm.toLowerCase().trim();
      filteredAllowlist = [];
      for (var i = 0; i < db.scores.length; i++) {
        if (db.scores[i].file.toLowerCase().includes(search)) {
          filteredAllowlist.push(db.scores[i].uid);
        }
      }
    }
    populateScoreList();
  }

  /**
   * Removes the specified file from the database
   *
   * file - the file to remove from the database
   */
  function removeFromDB(file) {
    for (var i = 0; i < db.scores.length; i++) {
      if (db.scores[i].file === file) {
        var id = db.scores[i].uid;
        // remove from scores
        db.scores.splice(i, 1);
        for (var prefix in db) {
          if (db[prefix]["scores"] !== undefined) {
            var j = 0;
            while (j < db[prefix]["scores"].length) {
              if (db[prefix]["scores"][j] === id) {
                // remove from any prefix indices
                db[prefix]["scores"].splice(j, 1);
              } else {
                j++;
              }
            }
          }
        }
        // close tag editor if it was active on the removed score
        if (id === uidOpenedTagEdit) {
          toggleTagEditSection(id);
        }
        break;
      }
    }
    saveData();
    populateScoreList();
  }

  /**
   * Checks the filter list to see if this score is allowed to be displayed
   *
   * uid - the id of the score to check
   */
  function isAllowed(uid) {
    return filteredAllowlist.length === 0 || filteredAllowlist.indexOf(uid) >= 0;
  }

  /**
   * Finds the position of a score in the database by its uid
   *
   * uid - the id of the score to get the position of
   */
  function uidToPos(uid) {
    for (var i = 0; i < db.scores.length; i++) {
      if (db.scores[i].uid === uid) return i;
    }
    return -1;
  }

  /**
   * Toggles the panel for editing tags
   *
   * uid - the id of the score that triggered the event
   */
  function toggleTagEditSection(uid) {
    if (uid !== undefined && (!isTagEditOpen || uid !== uidOpenedTagEdit)) {
      isTagEditOpen = true;
      uidOpenedTagEdit = uid;
      tagEditView.height = 200;
      tagEditView.visible = true;
      tagListModel.clear();
      var pos = uidToPos(uid);
      for (var prefix in db.scores[pos]) {
        if (prefix === "file" || prefix === "uid") continue;
        tagListModel.append({"uid": db.scores[pos].uid, "prefix": prefix, "tag": db.scores[pos][prefix]});
      }
    } else {
      isTagEditOpen = false;
      uidOpenedTagEdit = undefined;
      tagEditView.height = 0;
      tagEditView.visible = false;
    }
  }

  /**
   * Updates a score's tag for a given prefix
   *
   * uid - the id of the score to update
   * prefix - the prefix of the tag being edited
   * oldTag - the previous tag value
   * newTag - the new tag value
   */
  function updateTagByPrefix(uid, prefix, oldTag, newTag) {
    var pos = uidToPos(uid);
    db.scores[pos][prefix] = newTag;
    if (prefix !== "uid" && prefix !== "file" && prefix !== "title") {
      removeFromIndex(uid, prefix, oldTag);
      addToIndex(uid, prefix, newTag);
    }
    // TODO: update scoreListModel when a score's visible tags change
    saveData();
  }

  /**
   * Adds a score to an index on a prefix
   *
   * uid - the id of the score to be indexed
   * prefix - the prefix being indexed
   * tag - the tag that the score will be indexed under
   */
  function addToIndex(uid, prefix, tag) {
    if (db[prefix]) {
      for (var i = 0; i < db[prefix].length; i++) {
        if (db[prefix][i].tag === tag) {
          db[prefix][i].scores.push(uid);
          return;
        }
      }
      // prefix did not contain tag
      db[prefix].push({"tag": tag, "scores": [uid]});
    } else {
      // prefix not indexed
      db[prefix] = [{"tag": tag, "scores": [uid]}];
    }
  }

  /**
   * Removes a score from an index on a prefix
   *
   * uid - the id of the score to un-index
   * prefix - the prefix being indexed
   * tag - the tag that the score was indexed under
   */
  function removeFromIndex(uid, prefix, tag) {
    for (var i = 0; i < db[prefix].length; i++) {
      if (db[prefix][i].tag === tag && db[prefix][i].scores.indexOf(uid) !== -1) {
        db[prefix][i].scores.splice(db[prefix][i].scores.indexOf(uid), 1);
        // TODO
        // - delete tag in index if it contains no scores,
        // - delete index if it contains no tags
        break;
      }
    }
  }

  /**
   * Test file used to clean up database
   */
  FileIO { id: testFile }

  /**
   * The database file
   */
  FileIO { id: dbFile; source: dbPath; }

  /**
   * The tags for a selected score
   */
  ListModel { id: tagListModel; dynamicRoles: true }

  /**
   * The filtered scores shown in the grid
   */
  ListModel { id: scoreListModel }

  /**
   * The list of available files
   */
  FolderListModel {
    id: folderListModel
    nameFilters: ["*.mscz"]
    onFolderChanged: addFilesToDatabase(folderListModel)
  }

  /**
   * Dialog to select the score directory
   */
  FileDialog {
    id: libraryDialog
    title: "Select a folder to import"
    folder: shortcuts.documents
    selectFolder: true

    onAccepted: {
      folderListModel.folder = "";
      libraryDialog.close();
      folderListModel.folder = fileUrl;
    }
  }

  /**
   * Represents a score. Available fields:
   * - uid
   * - file
   * - title
   * - [any user-defined tags]
   */
  Component {
    id: scoreComponent

    Item {
      width: libraryListView.width
      height: 100

      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        color: "white"
        clip: true

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true

          onEntered: {
            trashIcon.visible = true;
            trash.enabled = true;
          }

           onExited: {
             trashIcon.visible = false;
             trash.enabled = false;
           }

          onClicked: {
            testFile.source = file;
            if (testFile.exists()) {
              toggleTagEditSection(uid);
              //readScore(file);
              if (libMan.pluginType === "dock") {
                //Qt.quit();
              }
            } else {
              fileNotExistPopup.open();
            }
          }

          Image {
            id: trashIcon
            anchors.top: parent.top
            anchors.right: parent.right
            width: 24
            height: 24
            source: "trash.png"
            visible: false
          }

          MouseArea {
            id: trash
            anchors.top: parent.top
            anchors.right: parent.right
            width: 24
            height: 24
            enabled: false
            hoverEnabled: true
            onClicked: confirmDeletePopup.open()
          }
        }

        Text {
          anchors.top: parent.top
          font.pixelSize: 16
          text: title ? title : ""
        }

        /**
         * Shown when trying to open a file that no longer exists
         */
        Popup {
          id: fileNotExistPopup
          width: fileNotExistText.width + 58
          height: 48
          modal: true
          focus: true

          Image {
            id: warnIcon
            anchors.top: parent.top
            anchors.left: parent.left
            width: 24
            height: 24
            source: "warn.png";
          }

          Text {
            id: fileNotExistText
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: warnIcon.right
            anchors.leftMargin: 10
            verticalAlignment: Text.AlignVCenter
            text: "Could not find " + title
          }
        }

        /**
         * Shown when clicking the "delete" trash can on a score
         */
        Popup {
          id: confirmDeletePopup
          width: 350
          height: 98
          modal: true
          focus: true

          Text {
            id: confirmDeleteText
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            horizontalAlignment: Text.AlignHCenter
            text: "Are you sure you want to remove this file from the database:"
          }

          Text {
            anchors.top: confirmDeleteText.bottom
            anchors.left: parent.left
            anchors.leftMargin: 10
            font.bold: true
            text: title
          }

          Button {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.leftMargin: 20
            text: "Remove"
            onClicked: {
              console.log("removing " + title);
              removeFromDB(file);
              confirmDeletePopup.close();
            }
          }

          Button {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.rightMargin: 20
            text: "Cancel"
            onClicked: confirmDeletePopup.close()
          }
        }
      }
    }
  }

  /**
   * Represents an editable tag. Available fields:
   * - uid
   * - prefix
   * - tag
   */
  Component {
    id: tagComponent

    Item {
      width: tagListView.width
      height: tagPair.height

      Rectangle {
        id: tagPair
        width: parent.width
        height: childrenRect.height
        color: "transparent"

        Text {
          id: prefixText
          anchors.left: parent.left
          anchors.leftMargin: 8
          color: "gray"
          text: prefix + " : "
        }

        TextInput {
          id: tagText
          anchors.left: prefixText.right
          selectByMouse: true
          text: tag

          onEditingFinished: {
            if (tag !== text) {
              updateTagByPrefix(uid, prefix, tag, text);
              tag = text;
            }
          }
        }
      }
    }
  }

  /**
   * The main window
   */
  Rectangle {
    anchors.fill: parent

    /**
     * The search label
     */
    Label {
      id: tagLabel
      anchors.top: parent.top
      anchors.left: parent.left
      height: tagInput.height
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 16
      text: "Search: "
    }

    /**
     * The search field
     */
    TextField {
      id: tagInput
      anchors.top: parent.top
      anchors.left: tagLabel.right
      anchors.right: parent.right

      onAccepted: {
        var scoreResult = searchDB(text);
        if (scoreResult) {
          console.log(scoreResult.path);
          readScore(scoreResult.path);
        }
      }
    }

    /**
     * Scroll view to allow list view to have many scores
     */
    ScrollView {
      id: libraryScrollView
      anchors.top: tagInput.bottom
      anchors.bottom: tagEditView.top
      width: parent.width
      clip: true
      background: Rectangle { anchors.fill: parent; implicitWidth: parent.width; color: "grey" }

      ScrollBar.horizontal.policy: ScrollBar.AsNeeded
      ScrollBar.vertical.policy: ScrollBar.AsNeeded

      /**
       * The list view displaying the filtered list of scores
       */
      ListView {
        id: libraryListView
        width: parent.width
        height: 100

        model: scoreListModel
        delegate: scoreComponent
      }
    }

    /**
     * The tag editing pane
     */
    Rectangle {
      id: tagEditView
      anchors.bottom: libraryCount.top
      width: parent.width
      height: 0
      border.color: "black"
      border.width: 1
      color: "white"
      visible: false

      /**
       * The shaded region for the pane's title
       */
      Rectangle {
        id: tagEditTitle
        anchors.top: parent.top
        anchors.left: parent.left
        width: parent.width
        height: childrenRect.height
        color: "gray"

        /**
         * The pane's title
         */
        Text { font.pixelSize: 24; text: "Tag Editor" }
      }

      /**
       * Scroll view to allow list to have many tags
       */
      ScrollView {
        id: tagListScrollView
        anchors.top: tagEditTitle.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        width: parent.width
        clip: true

        ScrollBar.horizontal.policy: ScrollBar.AsNeeded
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        /**
         * The list view displaying the tags for a given score
         */
        ListView {
          id: tagListView
          width: parent.width
          height: 60

          model: tagListModel
          delegate: tagComponent
        }
      }
    }

    /**
     * The number of scores loaded
     */
    Text {
      id: libraryCount
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.bottomMargin: 4
      anchors.leftMargin: 4
      height: 30
      width: 300
      verticalAlignment: Text.AlignBottom
    }

    /**
     * Button that opens the file dialog to find a new library path
     */
    Button {
      id: bOpenLibrary
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      height: 34
      width: 80
      text: "Add"
      onClicked: libraryDialog.open()
    }
  }

}
