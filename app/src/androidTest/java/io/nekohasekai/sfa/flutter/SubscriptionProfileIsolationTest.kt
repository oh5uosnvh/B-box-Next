package io.nekohasekai.sfa.flutter

import androidx.test.ext.junit.runners.AndroidJUnit4
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.sfa.Application
import io.nekohasekai.sfa.database.ProfileManager
import io.nekohasekai.sfa.database.Settings
import io.nekohasekai.sfa.database.TypedProfile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.IOException

@RunWith(AndroidJUnit4::class)
class SubscriptionProfileIsolationTest {
    private val args = mapOf<String, Any?>("name" to "Isolated subscription", "url" to "https://example.test/nodes",
        "autoUpdate" to true, "interval" to 120)

    private fun nodes(tag: String) = """{"outbounds":[{"type":"socks","tag":"$tag","server":"127.0.0.1","server_port":1080}]}"""
    private fun tags(content: String): Set<String> {
        val list = JSONObject(Libbox.formatConfig(content).value).optJSONArray("outbounds") ?: JSONArray()
        return (0 until list.length()).map { list.getJSONObject(it).getString("tag") }.toSet()
    }
    private fun files() = File(Application.application.filesDir, "configs").listFiles().orEmpty().map { it.path }.toSet()

    private fun fixture(block: suspend (BoxProfiles, Long) -> Unit) = runBlocking(Dispatchers.IO) {
        Application.application.setupLibbox()
        Settings.dataStore.initialize()
        val selection = Settings.selectedProfile
        val mode = Settings.serviceMode
        val existing = ProfileManager.list().map { it.id }.toSet()
        val profiles = BoxProfiles(beforeApply = {}) {}
        try {
            val original = profiles.save(mapOf("name" to "Isolation original", "content" to nodes("original-local")))
            Settings.saveProfileSelection(original)
            block(profiles, original)
        } finally {
            Settings.saveProfileSelection(selection, mode)
            for (profile in ProfileManager.list().filter { it.id !in existing }) {
                ProfileManager.delete(profile)
                File(profile.typed.path).delete()
            }
            Settings.dataStore.flush()
            io.nekohasekai.sfa.bg.UpdateProfileWork.reconfigureUpdater()
        }
    }

    @Test fun urlImportsCreateIndependentProfilesAndUpdatesStayIsolated() = fixture { profiles, original ->
        var incoming = nodes("source-one")
        val subscriptions = BoxNodeSubscriptions(beforeApply = {}, download = { incoming }) {}
        val before = profiles.read(original)
        val oldSources = profiles.get(original).typed.subscriptions
        val first = (subscriptions.importProfile(args + mapOf("profileId" to original, "profileRevision" to "ignored"))["profileId"] as Number).toLong()
        val second = (subscriptions.importProfile(args)["profileId"] as Number).toLong()
        assertNotEquals(original, first)
        assertNotEquals(first, second)
        assertEquals(original, Settings.selectedProfile)
        assertEquals(before, profiles.read(original))
        assertEquals(oldSources, profiles.get(original).typed.subscriptions)
        val created = profiles.get(first)
        assertEquals(TypedProfile.Type.Local, created.typed.type)
        assertFalse(created.typed.isDefault)
        assertEquals("", created.typed.remoteURL)
        assertEquals("Isolated subscription", created.name)
        assertFalse(tags(profiles.read(first)).contains("original-local"))
        val source = created.typed.subscriptions.single()
        assertEquals(args["url"], source.url)
        assertEquals(listOf("source-one"), source.tags)
        assertTrue(source.autoUpdate)
        assertEquals(120, source.interval)
        assertTrue(source.updatedAt > 0)
        assertNotEquals(source.id, profiles.get(second).typed.subscriptions.single().id)
        val secondBefore = profiles.read(second)
        incoming = nodes("source-updated")
        subscriptions.update(first, source.id)
        assertTrue(tags(profiles.read(first)).contains("source-updated"))
        assertFalse(tags(profiles.read(first)).contains("source-one"))
        assertEquals(before, profiles.read(original))
        assertEquals(secondBefore, profiles.read(second))
    }

    @Test fun failedDownloadOrParseCreatesNoProfileOrFile() = fixture { profiles, original ->
        val beforeIds = ProfileManager.list().map { it.id }
        val beforeFiles = files()
        val before = profiles.read(original)
        val failing = BoxNodeSubscriptions(beforeApply = {}, download = { throw IOException("HTTP 503") }) {}
        assertTrue(runCatching { failing.importProfile(args) }.isFailure)
        for (content in listOf("invalid subscription", "{\"outbounds\":[]}")) {
            val invalid = BoxNodeSubscriptions(beforeApply = {}, download = { content }) {}
            assertTrue(runCatching { invalid.importProfile(args) }.isFailure)
        }
        assertEquals(beforeIds, ProfileManager.list().map { it.id })
        assertEquals(beforeFiles, files())
        assertEquals(before, profiles.read(original))
        assertEquals(original, Settings.selectedProfile)
    }

    @Test fun firstProfileActivationFailureRollsBackFileDatabaseAndSelection() = fixture { profiles, original ->
        val beforeIds = ProfileManager.list().map { it.id }
        val beforeFiles = files()
        val before = profiles.read(original)
        Settings.selectedProfile = -1L
        val subscriptions = BoxNodeSubscriptions(beforeApply = {}, download = { nodes("rejected") }) { recover ->
            if (!recover) throw IOException("Activation failed")
        }
        assertTrue(runCatching { subscriptions.importProfile(args) }.isFailure)
        assertEquals(-1L, Settings.selectedProfile)
        assertEquals(beforeIds, ProfileManager.list().map { it.id })
        assertEquals(beforeFiles, files())
        assertEquals(before, profiles.read(original))
    }

    @Test fun parsedNodeImportsUseFreshTemplatesAndLeaveOriginalUntouched() = fixture { profiles, original ->
        val before = profiles.read(original)
        val parsed = Libbox.parseUINodes(nodes("isolated-local")).value
        val id = profiles.save(mapOf("name" to "Imported node file", "nodes" to parsed))
        assertNotEquals(original, id)
        assertEquals(original, Settings.selectedProfile)
        assertEquals(before, profiles.read(original))
        assertTrue(tags(profiles.read(id)).contains("isolated-local"))
        assertFalse(tags(profiles.read(id)).contains("original-local"))
        assertTrue(profiles.get(id).typed.subscriptions.isEmpty())
        val beforeIds = ProfileManager.list().map { it.id }
        val beforeFiles = files()
        assertTrue(runCatching { profiles.save(mapOf("name" to "Empty nodes", "nodes" to "{\"nodes\":[]}")) }.isFailure)
        assertEquals(beforeIds, ProfileManager.list().map { it.id })
        assertEquals(beforeFiles, files())
    }

    @Test fun explicitSubscriptionImportStillAppendsWithoutCreatingAProfile() = fixture { profiles, original ->
        val beforeIds = ProfileManager.list().map { it.id }
        val subscriptions = BoxNodeSubscriptions(beforeApply = {}, download = { nodes("appended") }) {}
        subscriptions.importSubscription(args + mapOf("profileId" to original,
            "profileRevision" to BoxProfiles.revision(profiles.read(original))))
        assertEquals(beforeIds, ProfileManager.list().map { it.id })
        assertTrue(tags(profiles.read(original)).containsAll(listOf("original-local", "appended")))
        assertEquals(listOf("appended"), profiles.get(original).typed.subscriptions.single().tags)
        assertEquals(original, Settings.selectedProfile)
    }
}
