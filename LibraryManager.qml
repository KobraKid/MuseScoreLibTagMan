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

  /** Populates score list from database. */
  function populateScoreList() {
    // Remove filtered/deleted scores
    for (var i = scoreListModel.count - 1; i > 0; i--) {
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

  /** Searches specified folder for scores not yet in the database. */
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

  /** Saves database to file. */
  function saveData() {
    dbFile.write(JSON.stringify(db));
  }

  /** Searches the database for the given term. */
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
            console.log("found scores " + db[prefix][i].scores);
            for (var j = 0; j < db[prefix][i].scores.length; j++) {
              filteredAllowlist.push(db.scores[db[prefix][i].scores[j]].uid);
            }
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

  /** Removes the specified file from the database. */
  function removeFromDB(file) {
    for (var i = 0; i < db.scores.length; i++) {
      if (db.scores[i].file === file) {
        var id = db.scores[i].uid;
        db.scores.splice(i, 1);
        for (var prefix in db) {
          if (db[prefix]["scores"] !== undefined) {
            var j = 0;
            while (j < db[prefix]["scores"].length) {
              if (db[prefix]["scores"][j] === id) {
                db[prefix]["scores"].splice(j, 1);
              } else {
                j++;
              }
            }
          }
        }
        break;
      }
    }
    saveData();
    populateScoreList();
  }

  /** Checks the filter list to see if this score is allowed to be displayed. */
  function isAllowed(uid) {
    return filteredAllowlist.length === 0 || filteredAllowlist.indexOf(uid) >= 0;
  }

  /** Finds the index of a score by its uid. */
  function uidToIndex(uid) {
    for (var i = 0; i < db.scores.length; i++) {
      if (db.scores[i].uid === uid) return i;
    }
    return -1;
  }

  /** Toggles the panel for editing tags. */
  function toggleTagEditSection(uid) {
    isTagEditOpen = !isTagEditOpen;
    if (isTagEditOpen) {
      tagEditView.height = 200;
      tagEditView.visible = true;
      tagListModel.clear();
      var index = uidToIndex(uid);
      for (var prefix in db.scores[index]) {
        if (prefix === "file" || prefix === "uid") continue;
        tagListModel.append({"uid": db.scores[index].uid, "prefix": prefix, "tag": db.scores[index][prefix]});
      }
    } else {
      tagEditView.height = 0;
      tagEditView.visible = false;
    }
  }

  /** Test file used to clean up database. */
  FileIO { id: testFile }

  /** The database file. */
  FileIO { id: dbFile; source: dbPath; }

  ListModel { id: tagListModel; dynamicRoles: true }

  /** The filtered scores shown in the grid. */
  ListModel { id: scoreListModel }

  /** The list of available files. */
  FolderListModel {
    id: folderListModel
    nameFilters: ["*.mscz"]

    onFolderChanged: addFilesToDatabase(folderListModel)
  }

  /** Dialog to select the score directory. */
  FileDialog {
    id: libraryDialog
    title: qsTr("Select a folder to import")
    folder: shortcuts.documents
    selectFolder: true

    onAccepted: {
      folderListModel.folder = "";
      libraryDialog.close();
      folderListModel.folder = fileUrl;
    }
  }

  /** An abstract score. */
  Component {
    id: scoreComponent

    /** The score item. */
    Item {
      width: libraryListView.width
      height: 100

      /** The visible part of the score item. */
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
              console.log(uid);
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

        /** Shown when trying to open a file that no longer exists. */
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

        /** Shown when clicking the "delete" trash can on a score. */
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

  Component {
    id: tagComponent

    Item {
      width: tagListView.width
      height: tagPair.height

      Rectangle {
        id: tagPair
        width: parent.width
        height: childrenRect.height

        TextInput {
          id: prefixText
          anchors.left: parent.left
          anchors.leftMargin: 10
          selectByMouse: true
          text: prefix

          onEditingFinished: {
            // TODO
          }
        }

        Text {
          id: colon
          anchors.left: prefixText.right
          text: " : "
        }

        TextInput {
          id: tagText
          anchors.left: colon.right
          selectByMouse: true
          text: tag

          onEditingFinished: {
            // TODO
          }
        }
      }
    }
  }

  /** The main window. */
  Rectangle {
    anchors.fill: parent

    /** The search label. */
    Label {
      id: tagLabel
      anchors.top: parent.top
      anchors.left: parent.left
      height: tagInput.height
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 16
      text: "Search: "
    }

    /** The search field. */
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

    /** Scroll view to allow list view to have many scores. */
    ScrollView {
      id: libraryScrollView
      anchors.top: tagInput.bottom
      anchors.bottom: tagEditView.top
      width: parent.width
      clip: true
      background: Rectangle { anchors.fill: parent; implicitWidth: parent.width; color: "grey" }

      ScrollBar.horizontal.policy: ScrollBar.AsNeeded
      ScrollBar.vertical.policy: ScrollBar.AsNeeded

      /** The list view displaying the filtered list of scores. */
      ListView {
        id: libraryListView
        width: parent.width
        height: 100

        model: scoreListModel
        delegate: scoreComponent
      }
    }

    Rectangle {
      id: tagEditView
      anchors.bottom: libraryCount.top
      width: parent.width
      height: 0
      border.color: "black"
      border.width: 1
      color: "white"
      visible: false

      Rectangle {
        id: tagEditTitle
        anchors.top: parent.top
        anchors.left: parent.left
        width: parent.width
        height: childrenRect.height
        color: "gray"

        Text {
          font.pixelSize: 24;
          text: "Tag Editor"
        }
      }

      ListView {
        id: tagListView
        anchors.top: tagEditTitle.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        model: tagListModel
        delegate: tagComponent
      }
    }

    /** The number of scores loaded. */
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

    /** Button that opens the file dialog to find a new library path. */
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
