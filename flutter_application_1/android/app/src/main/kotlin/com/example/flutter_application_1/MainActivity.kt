package com.example.flutter_application_1

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import de.dennisjacob.whatsapp_stickers_handler.WhatsappStickersHandler
import de.dennisjacob.whatsapp_stickers_handler.StickerPack
import de.dennisjacob.whatsapp_stickers_handler.StickerPackStorageService
import de.dennisjacob.whatsapp_stickers_handler.StickerPackValidator

class MainActivity : FlutterActivity() {
	private val channelName = "whatsapp_stickers_handler/refresh"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"addStickerPackAndEnable" -> {
						val stickerPack = buildStickerPack(call, "1")
						if (stickerPack == null) {
							result.error("400", "Missing sticker pack fields", null)
							return@setMethodCallHandler
						}

						try {
							StickerPackValidator.checkStickerPack(stickerPack)
							StickerPackStorageService.addStickerPack(applicationContext, stickerPack)
							launchEnableStickerPack(stickerPack)
							notifyStickerPackChanged(stickerPack.identifier)
							result.success(true)
						} catch (e: Exception) {
							result.error("500", "Failed to add pack", e.message)
						}
					}
					"updateStickerPackAndEnable" -> {
						val identifier = call.argument<String>("identifier")
						if (identifier.isNullOrBlank()) {
							result.error("400", "Missing pack identifier", null)
							return@setMethodCallHandler
						}

						val existing = StickerPackStorageService.getStickerPacks(applicationContext)
							.firstOrNull { it.identifier == identifier }
						val nextVersion = ((existing?.imageDataVersion ?: "0").toIntOrNull() ?: 0) + 1

						val stickerPack = buildStickerPack(call, nextVersion.toString())
						if (stickerPack == null) {
							result.error("400", "Missing sticker pack fields", null)
							return@setMethodCallHandler
						}

						try {
							StickerPackValidator.checkStickerPack(stickerPack)
							StickerPackStorageService.updateStickerPack(applicationContext, stickerPack)
							launchEnableStickerPack(stickerPack)
							notifyStickerPackChanged(stickerPack.identifier)
							result.success(true)
						} catch (e: Exception) {
							result.error("500", "Failed to update pack", e.message)
						}
					}
					"requestEnableStickerPack" -> {
						val packId = call.argument<String>("identifier")
						val packName = call.argument<String>("name")
						if (packId.isNullOrBlank() || packName.isNullOrBlank()) {
							result.error("400", "Missing pack identifier or name", null)
							return@setMethodCallHandler
						}

						val authority = WhatsappStickersHandler.getContentProviderAuthority(
							applicationContext
						)

						try {
							launchEnableStickerPack(packId, packName, authority)
							result.success(true)
						} catch (e: ActivityNotFoundException) {
							result.error("404", "WhatsApp not found", null)
						} catch (e: Exception) {
							result.error("500", "Failed to launch WhatsApp", e.message)
						}
					}
					else -> result.notImplemented()
				}
			}
	}

	private fun buildStickerPack(call: io.flutter.plugin.common.MethodCall, imageDataVersion: String): StickerPack? {
		val identifier = call.argument<String>("identifier")
		val name = call.argument<String>("name")
		val publisher = call.argument<String>("publisher")
		val trayImage = call.argument<String>("trayImage")
		val stickers = call.argument<List<String>>("stickers")
		if (identifier.isNullOrBlank() || name.isNullOrBlank() || publisher.isNullOrBlank() ||
			trayImage.isNullOrBlank() || stickers == null) {
			return null
		}

		val animatedStickerPack = call.argument<Boolean>("animatedStickerPack") == true
		val publisherEmail = call.argument<String>("publisherEmail")
		val publisherWebsite = call.argument<String>("publisherWebsite")
		val privacyPolicyWebsite = call.argument<String>("privacyPolicyWebsite")
		val licenseAgreementWebsite = call.argument<String>("licenseAgreementWebsite")
		val iosAppStoreLink = call.argument<String>("iosAppStoreLink")
		val androidPlayStoreLink = call.argument<String>("androidPlayStoreLink")

		return StickerPack(
			identifier,
			name,
			publisher,
			trayImage,
			stickers,
			imageDataVersion,
			animatedStickerPack,
			publisherEmail,
			publisherWebsite,
			privacyPolicyWebsite,
			licenseAgreementWebsite,
			iosAppStoreLink,
			androidPlayStoreLink,
		)
	}

	private fun notifyStickerPackChanged(identifier: String) {
		val authority = WhatsappStickersHandler.getContentProviderAuthority(applicationContext)
		val metadataAll = Uri.parse("content://$authority/metadata")
		val metadataOne = Uri.parse("content://$authority/metadata/$identifier")
		val stickers = Uri.parse("content://$authority/stickers/$identifier")

		val resolver = applicationContext.contentResolver
		resolver.notifyChange(metadataAll, null)
		resolver.notifyChange(metadataOne, null)
		resolver.notifyChange(stickers, null)
	}

	private fun launchEnableStickerPack(stickerPack: StickerPack) {
		val authority = WhatsappStickersHandler.getContentProviderAuthority(applicationContext)
		launchEnableStickerPack(stickerPack.identifier, stickerPack.name, authority)
	}

	private fun launchEnableStickerPack(identifier: String, name: String, authority: String) {
		val intent = Intent().apply {
			action = "com.whatsapp.intent.action.ENABLE_STICKER_PACK"
			putExtra("sticker_pack_id", identifier)
			putExtra("sticker_pack_name", name)
			putExtra("sticker_pack_authority", authority)
		}

		val packageManager = applicationContext.packageManager
		val whatsappPackage = when {
			isPackageInstalled(packageManager, "com.whatsapp") -> "com.whatsapp"
			isPackageInstalled(packageManager, "com.whatsapp.w4b") -> "com.whatsapp.w4b"
			else -> null
		}

		if (whatsappPackage != null) {
			intent.`package` = whatsappPackage
			startActivityForResult(intent, 200)
		} else {
			throw ActivityNotFoundException("WhatsApp not found")
		}
	}

	private fun isPackageInstalled(packageManager: android.content.pm.PackageManager, packageName: String): Boolean {
		return try {
			packageManager.getPackageInfo(packageName, 0)
			true
		} catch (_: Exception) {
			false
		}
	}
}
